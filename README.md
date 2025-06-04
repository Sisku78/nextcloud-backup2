# Nextcloud Full Backup Script

Backup completo y automatizado para una instancia de Nextcloud ejecutándose en Docker, con soporte para:

* Respaldo de base de datos y configuración
* Compresión y cifrado de archivos sensibles
* Almacenamiento seguro en repositorio Borg
* Subida opcional a Google Drive y QNAP vía Rclone
* Logs cifrados y notificaciones por correo electrónico
* Ejecución desatendida (cron compatible)

---

## 🗂 Estructura del proyecto

```
nextcloud-backup/
├── full_backup_config.env         # Configuración general (sin contraseñas)
├── .env.sec                       # Archivo oculto con contraseñas (no subir a Git)
├── full_backup_nextcloud_v2.sh   # Script principal
└── README.md                      # Documentación
```

---

## ⚙️ Requisitos

* Linux (Debian/Ubuntu)
* `docker` y `docker-compose`
* `borgbackup`
* `rclone`
* `gpg` y claves configuradas
* `7z` (`p7zip-full`)
* `mailutils` para notificaciones por correo

Instalación rápida:

```bash
apt update && apt install -y borgbackup rclone gnupg p7zip-full mailutils
```

---

## 🔐 Archivos de configuración

### `full_backup_config.env`

Contiene variables no sensibles. Ejemplo:

```env
dbUser=root
nextcloudDatabase=nextcloud_database
recipientEmail=tu_correo@ejemplo.com
backupDiscMount=/mnt/backups/nextcloud/
nextcloudImage=lscr.io/linuxserver/nextcloud
...
```

### `.env.sec`

Variables sensibles (protegidas por permisos):

```bash
dbPassword='tu_pass_db'
borgPassphrase='tu_pass_borg'
zipPassword='pass_para_7z'
```

**Importante:**

```bash
chmod 600 .env.sec
```

---

## 🚀 Ejecución manual

```bash
sudo ./full_backup_nextcloud_v2.sh
```

## ⏱ Automatización con cron

```bash
sudo crontab -e
```

Y añade:

```cron
0 3 * * * /ruta/al/script/full_backup_nextcloud_v2.sh >> /var/log/nextcloud_backup_cron.log 2>&1
```

---

## 📤 Subida a Google Drive / QNAP

Controlado por variables:

```env
ENABLE_RCLONE_UPLOAD_GOOGLE=false
ENABLE_RCLONE_UPLOAD_QNAP=true
```

Configura previamente `rclone config` con remotos `mydrive2:` y `Qnap:`.

---

## 🔒 Seguridad

* Contraseñas están fuera del repositorio (`.env.sec`)
* Logs sensibles se cifran con GPG automáticamente
* Script comprueba integridad con `borg check`

---

## 📧 Notificación por correo

Requiere tener configurado `mail` y `postfix` o similar.

El correo contiene:

* Resultado del backup
* Estado de la subida
* Duración y uso de disco

---

## 🧪 Restauración (pendiente de implementar)

* Restaurar `.7z` con claves GPG y contraseña ZIP
* Extraer imágenes Docker y configuración
* Restaurar desde repositorio Borg

---

## 📦 Licencia

MIT — Úsalo, modifícalo y mejora.

---

## 🤝 Contribuciones

Pull requests bienvenidas si mejoras seguridad, compatibilidad o portabilidad.

## 📄 Documentación adicional

- [Extra: Configuración de Rclone SFTP con QNAP](Rclone_SFTP_QNAP_Setup.md)
