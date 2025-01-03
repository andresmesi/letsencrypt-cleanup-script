#!/bin/bash

BASE_DIR="/etc/letsencrypt"
LIVE_DIR="${BASE_DIR}/live"
RENEWAL_DIR="${BASE_DIR}/renewal"
ARCHIVE_DIR="${BASE_DIR}/archive"
CSR_DIR="${BASE_DIR}/csr"
KEYS_DIR="${BASE_DIR}/keys"
BACKUP_FILE="/etc/letsencrypt.tar.gz"
LOCKFILE="/var/run/letsencrypt_cleanup.lock"
LOGFILE="/var/log/letsencrypt_cleanup.log"

EXECUTE=false
RECOVER=false

# Redirigir salida a un archivo de log
exec > >(tee -a "$LOGFILE") 2>&1

# Verificar si el script ya está en ejecución
if [ -e "$LOCKFILE" ]; then
    echo "El script ya está en ejecución." >&2
    exit 1
fi
trap 'rm -f "$LOCKFILE"' EXIT
touch "$LOCKFILE"

if [ "$1" == "ejecutar" ]; then
    EXECUTE=true
elif [ "$1" == "recuperar" ]; then
    RECOVER=true
fi

# Modo de recuperación
if [ "$RECOVER" = true ]; then
    echo "Recuperando backup desde ${BACKUP_FILE}..."
    if [ -f "$BACKUP_FILE" ]; then
        tar -xzf "$BACKUP_FILE" -C /etc
        echo "Recuperación completada."
    else
        echo "Error: No se encontró el archivo de backup ${BACKUP_FILE}."
    fi
    exit 0
fi

# Crear backup si está en modo ejecución
if [ "$EXECUTE" = true ]; then
    echo "Creando backup de /etc/letsencrypt en ${BACKUP_FILE}..."
    tar -czf "$BACKUP_FILE" "$BASE_DIR"
    echo "Backup creado."
fi

echo "Iniciando análisis de limpieza de Let's Encrypt..."

# Obtener dominios activos desde /live y /renewal
ACTIVE_DOMAINS=$(ls -1 ${LIVE_DIR} | grep -v "README")
RENEWAL_DOMAINS=$(ls -1 ${RENEWAL_DIR} | grep -E "\.conf$" | sed 's/\.conf$//')

ALL_ACTIVE_DOMAINS=$(echo -e "${ACTIVE_DOMAINS}\n${RENEWAL_DOMAINS}" | sort | uniq)

# Limpiar /archive
echo "Analizando /archive..."
for DOMAIN in $(ls -1 ${ARCHIVE_DIR}); do
    if ! echo "${ALL_ACTIVE_DOMAINS}" | grep -qw "${DOMAIN}"; then
        echo "Se eliminarán archivos obsoletos para dominio: ${DOMAIN}"
        if [ "$EXECUTE" = true ]; then
            rm -rf "${ARCHIVE_DIR}/${DOMAIN}"
        fi
    else
        echo "Revisando archivos innecesarios en ${DOMAIN}..."
        LIVE_FILES=$(find "${LIVE_DIR}/${DOMAIN}" -type l -exec readlink {} \; | xargs -n 1 basename)
        ARCHIVE_FILES=$(ls -1 "${ARCHIVE_DIR}/${DOMAIN}")
        for FILE in ${ARCHIVE_FILES}; do
            if ! echo "${LIVE_FILES}" | grep -qw "${FILE}"; then
                echo "Se eliminará archivo no referenciado: ${ARCHIVE_DIR}/${DOMAIN}/${FILE}"
                if [ "$EXECUTE" = true ]; then
                    rm -f "${ARCHIVE_DIR}/${DOMAIN}/${FILE}"
                fi
            fi
        done
    fi
done

# Limpiar /csr y /keys según antigüedad
DAYS=90
echo "Analizando /csr y /keys para eliminar archivos mayores a ${DAYS} días..."
find "$CSR_DIR" -type f -mtime +$DAYS | while read FILE; do
    echo "Se eliminará CSR obsoleto: ${FILE}"
    if [ "$EXECUTE" = true ]; then
        rm -f "$FILE"
    fi
done

find "$KEYS_DIR" -type f -mtime +$DAYS | while read FILE; do
    echo "Se eliminará clave obsoleta: ${FILE}"
    if [ "$EXECUTE" = true ]; then
        rm -f "$FILE"
    fi
done

if [ "$EXECUTE" = true ]; then
    echo "Limpieza de Let's Encrypt completada."
else
    echo "Ejecución en modo análisis. Use el parámetro 'ejecutar' para realizar los cambios o 'recuperar' para restaurar el backup."
fi
