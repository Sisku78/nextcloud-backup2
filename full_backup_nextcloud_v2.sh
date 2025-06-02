#!/bin/bash
##################################
### Full Backup v.1.0 (mejorado con verificación global)
##################################

umask 002

CONFIG_PATH="/root/scripts/nextcloud-backup/full_backup_config.env"
SECRETS_PATH="/root/scripts/nextcloud-backup/.env.sec"

# Cargar configuración general
if [ -f "$CONFIG_PATH" ]; then
    source "$CONFIG_PATH"
else
    echo "ERROR: No se pudo cargar el archivo de configuración general '$CONFIG_PATH'."
    exit 1
fi

# Cargar variables sensibles
if [ -f "$SECRETS_PATH" ]; then
    source "$SECRETS_PATH"
else
    echo "ERROR: No se pudo cargar el archivo de secretos '$SECRETS_PATH'."
    exit 1
fi

if [ "$ENABLE_DEBUG" == "true" ]; then set -x; else set +x; fi

echo "$(date): El script fue ejecutado por $(whoami)" >> /var/log/backup_script_access.log

if [[ -z "$dbUser" || -z "$dbPassword" || -z "$nextcloudDatabase" || -z "$borgPassphrase" || -z "$logDirectory" || -z "$recipientEmail" || -z "$gpgPublicKeyPath" || -z "$gpgPrivateKeyPath" || -z "$localBackupDir" || -z "$readmeFilePath" || -z "$borgKeyPath" || -z "$webserverServiceName" || -z "$nextcloudImage" || -z "$mariadbImage" || -z "$backupDiscMount" || -z "$configDir" || -z "$nextcloudComposeDir" || -z "$rcloneRemotePath" || -z "$rcloneRemotePathQNAP" || -z "$ENABLE_RCLONE_UPLOAD_GOOGLE" || -z "$ENABLE_RCLONE_UPLOAD_QNAP" ]]; then
    echo "ERROR: Faltan variables esenciales en el archivo de configuración."
    exit 1
fi

export BORG_PASSPHRASE="$borgPassphrase"
export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes
export GPG_TTY=$(tty)

startTime=$(date +%s)
currentDate=$(date --date @"$startTime" +"%Y%m%d_%H%M%S")
currentDateReadable=$(date --date @"$startTime" +"%d.%m.%Y - %H:%M:%S")
logFile="${logDirectory}/${currentDate}.log"

backupStatus="OK"
rcloneStatus="OK"

mkdir -p "${logDirectory}" || { echo "Error al crear directorio de logs"; exit 1; }

notify_error() {
    local error_message="$1"
    backupStatus="ERROR"
    echo "$error_message" >> "${logFile}"
    echo "$error_message" | mail -s "Error en Backup Nextcloud: ${currentDateReadable}" "$recipientEmail"
}

cleanup() {
    echo "Restableciendo servicios..."
    systemctl start "${webserverServiceName}"
    docker exec -i nextcloud occ maintenance:mode --off
    echo "Servicios restablecidos."
}

exec &> >(tee -i "${logFile}")
trap cleanup EXIT

if [ "$(id -u)" != "0" ]; then notify_error "Debe ejecutarse como root"; exit 1; fi
if [ ! -d "${localBackupDir}" ]; then notify_error "Directorio temporal no existe"; exit 1; fi

echo -e "\n###### Inicio del Backup: ${currentDateReadable} ######\n"
echo -e "Preparando los datos..."
dpkg --get-selections > "${localBackupDir}/software.list"

if [[ -f "${readmeFilePath}" && -f "${gpgPublicKeyPath}" && -f "${gpgPrivateKeyPath}" && -f "${borgKeyPath}" ]]; then
    tar -czf "${localBackupDir}/${currentDate}-restoration_files.tar.gz" \
        "${readmeFilePath}" "${gpgPublicKeyPath}" "${gpgPrivateKeyPath}" "${borgKeyPath}"
    7z a -p"$zipPassword" "${localBackupDir}/${currentDate}-restoration_files.7z" \
        "${localBackupDir}/${currentDate}-restoration_files.tar.gz" || notify_error "Error al comprimir restoration_files.tar.gz"
    rm -f "${localBackupDir}/${currentDate}-restoration_files.tar.gz"
else
    notify_error "Faltan archivos para restoration_files.tar.gz"
    exit 1
fi

docker exec -i nextcloud occ maintenance:mode --on
systemctl stop "${webserverServiceName}"

echo "Creando respaldo de la base de datos..."
docker exec nextcloud-mariadb mysqldump --single-transaction --routines -h localhost -u"$dbUser" -p"$dbPassword" "$nextcloudDatabase" | gzip > "${localBackupDir}/${currentDate}-nextcloud-db.sql.gz"

docker save -o "${localBackupDir}/${currentDate}-nextcloud-image.tar" "${nextcloudImage}"
docker save -o "${localBackupDir}/${currentDate}-mariadb-image.tar" "${mariadbImage}"

echo "Creando respaldo en Borg..."
borg create --stats --verbose --progress --compression zstd,15 "${backupDiscMount}::${currentDate}-full-backup-nextcloud" \
    "${localBackupDir}/${currentDate}-nextcloud-db.sql.gz" \
    "${configDir}" \
    "${nextcloudComposeDir}" \
    "${localBackupDir}/${currentDate}-nextcloud-image.tar" \
    "${localBackupDir}/${currentDate}-mariadb-image.tar" \
    "${localBackupDir}/${currentDate}-restoration_files.7z"

rm -fv "${localBackupDir}"/*.{sql.gz,tar,7z}
echo "Comprobando integridad..."
borg check "${backupDiscMount}" || notify_error "Error en check de backup"

systemctl start "${webserverServiceName}"
docker exec -i nextcloud occ maintenance:mode --off
rm "${localBackupDir}/software.list"

echo "Limpiando backups antiguos..."
trap 'notify_error "Error al limpiar backups antiguos."; exit 1' ERR
borg prune --progress --stats "${backupDiscMount}" --glob-archives '?????????_??????-full-backup-nextcloud' --keep-last=5
trap - ERR

echo "Limpiando temporales y logs antiguos..."
rm -rf "${localBackupDir:?}/*"
find "${logDirectory}" -type f -name "*.log" -mtime +15 -exec rm -- {} \;
find "${logDirectory}" -type f -name "*-rclone*.log.gpg" -mtime +7 -exec rm -- {} \;

# ---------- SUBIDAS CON RCLONE ------------
max_retries=3

if [ "$ENABLE_RCLONE_UPLOAD_GOOGLE" == "true" ]; then
    echo "Subiendo backup a Google Drive..."
    retry_count=0
    while [ $retry_count -lt $max_retries ]; do
        if rclone copy "${backupDiscMount}" "${rcloneRemotePath}" --log-file="${logFile}-rclone-google.log" --verbose; then
            rcloneGoogleStatus="La copia a Google Drive se realizó con éxito."
            break
        else
            rcloneGoogleStatus="Error en subida a Google Drive. Reintentando..."
            retry_count=$((retry_count+1))
            sleep 5
        fi
    done
else
    rcloneGoogleStatus="Subida a Google Drive deshabilitada."
fi

if [ "$ENABLE_RCLONE_UPLOAD_QNAP" == "true" ]; then
    echo "Subiendo backup a QNAP..."
    retry_count=0
    while [ $retry_count -lt $max_retries ]; do
        if rclone copy "${backupDiscMount}" "${rcloneRemotePathQNAP}" --log-file="${logFile}-rclone-qnap.log" --verbose; then
            rcloneQnapStatus="La copia a QNAP se realizó con éxito."
            break
        else
            rcloneQnapStatus="Error en subida a QNAP. Reintentando..."
            retry_count=$((retry_count+1))
            sleep 5
        fi
    done
else
    rcloneQnapStatus="Subida a QNAP deshabilitada."
fi

# Evaluar estado final de subidas Rclone
echo "Evaluando estado final de Rclone..."
if [[ "$rcloneGoogleStatus" != *"éxito"* || "$rcloneQnapStatus" != *"éxito"* ]]; then
    rcloneStatus="ERROR"
fi

echo "Encriptando logs de Rclone..."
for log in "${logFile}-rclone-google.log" "${logFile}-rclone-qnap.log"; do
    if [ -f "$log" ]; then
        gpg --batch --yes --output "${log}.gpg" --encrypt --recipient "$recipientEmail" "$log" && rm "$log"
    fi
done

# ---------- EMAIL RESUMEN ----------
endTime=$(date +%s)
endDateReadable=$(date --date @"$endTime" +"%d.%m.%Y - %H:%M:%S")
duration=$((endTime-startTime))
durationReadable=$(printf "%02d horas %02d minutos %02d segundos" $((duration/3600)) $(((duration/60)%60)) $((duration%60)))

mail -s "Backup Nextcloud: ${currentDateReadable}" "$recipientEmail" <<EOF
El backup de Nextcloud ha finalizado.

Fecha de inicio: ${currentDateReadable}
Fecha de finalización: ${endDateReadable}
Duración total: ${durationReadable}

🔐 Estado general del backup: $backupStatus
☁️ Estado de la subida Rclone: $rcloneStatus

Resultado Google Drive:
${rcloneGoogleStatus}

Resultado QNAP:
${rcloneQnapStatus}

Uso del disco:
$(df -h "${backupDiscMount}")
EOF

gpg --batch --yes --output "${logFile}.gpg" --encrypt --recipient "$recipientEmail" "${logFile}" && rm -f "${logFile}"

exit 0
