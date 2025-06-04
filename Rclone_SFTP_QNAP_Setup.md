# Extra: Configuración de acceso SFTP con clave pública al QNAP para Rclone

Este documento explica cómo configurar el acceso SFTP al QNAP usando clave pública SSH para permitir que Rclone realice copias de seguridad de forma segura y automatizada sin contraseñas.

---

## ✅ Requisitos previos

* Tener Rclone configurado en tu servidor (`rclone config` con `type = sftp`, `key_use_agent = true`)
* Tener una clave SSH generada localmente (`~/.ssh/id_rsa`)
* Tener el servicio SSH habilitado en el QNAP

---

## 🛠 Paso 1: Habilitar SSH en el QNAP

1. Inicia sesión en la interfaz web del QNAP
2. Ve a **Panel de control > Terminal y SNMP > Servicio de Terminal**
3. Marca **Habilitar el servicio SSH**
4. Verifica el puerto (por defecto: 22)

---

## 🛠 Paso 2: Copiar la clave pública al QNAP

Desde tu servidor (Linux), ejecuta:

```bash
ssh-copy-id -i ~/.ssh/id_rsa.pub admin@192.168.1.50
```

Reemplaza:

* `admin` con el usuario habilitado en tu QNAP
* `192.168.1.50` con la IP de tu QNAP

Esto copia tu clave pública al archivo `~/.ssh/authorized_keys` del QNAP y permite login sin contraseña.

---

## 🛡️ Verificación de acceso

Desde tu servidor:

```bash
ssh admin@192.168.1.50
```

✔️ Si accedes sin contraseña, el acceso con clave pública está funcionando.

---

## 🔁 Verificación con Rclone

Ejecuta:

```bash
rclone ls Qnap:
```

Debe listar archivos o confirmar que el remoto está accesible sin errores.

---

## 🔒 Permisos correctos en el QNAP

En el QNAP, asegúrate de que:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

Estos permisos son necesarios para que el SSH acepte la clave pública.

---

## 📄 Archivo de configuración Rclone asociado

```ini
[Qnap]
type = sftp
host = 192.168.1.50
user = admin
key_use_agent = true
```

---

## ✅ Resultado

Una vez completado este proceso:

* Rclone podrá subir backups al QNAP sin necesidad de contraseña
* El acceso será seguro y automatizado mediante `ssh-agent`
* Puedes usar esta configuración en tu script de backup con confianza

---

## 💡 Recomendación

Guarda este procedimiento como plantilla (`Rclone_SFTP_QNAP_Setup.md`) dentro de tu repositorio para reutilizarlo en futuras reinstalaciones o migraciones.
