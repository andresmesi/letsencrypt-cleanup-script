#!/bin/bash

BASE_DIR="/etc/letsencrypt"
LIVE_DIR="${BASE_DIR}/live"
RENEWAL_DIR="${BASE_DIR}/renewal"
ARCHIVE_DIR="${BASE_DIR}/archive"
CSR_DIR="${BASE_DIR}/csr"
KEYS_DIR="${BASE_DIR}/keys"
BACKUP_FILE="/etc/letsencrypt.tar.gz"
LOCKFILE="/var/run/letsencrypt_cleanup.lock"
LOGFILE="${BASE_DIR}/letsencrypt_cleanup.log"

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

# Limpiar /archive y dominios inactivos en /live y /renewal según antigüedad
DAYS=90
echo "Analizando /archive, /live y /renewal para dominios con certificados mayores a ${DAYS} días..."
for DOMAIN in $(ls -1 ${ARCHIVE_DIR}); do
    LAST_MODIFIED=$(find "${ARCHIVE_DIR}/${DOMAIN}" -type f -printf '%T@\n' | sort -n | tail -1 | cut -d '.' -f 1)
    CURRENT_TIME=$(date +%s)
    AGE=$(( (CURRENT_TIME - LAST_MODIFIED) / 86400 ))

    if [ "$AGE" -gt "$DAYS" ]; then
        echo "Dominio ${DOMAIN} tiene certificados obsoletos (${AGE} días). Eliminando..."
        if [ "$EXECUTE" = true ]; then
            rm -rf "${ARCHIVE_DIR}/${DOMAIN}"
            rm -rf "${LIVE_DIR}/${DOMAIN}"
            rm -f "${RENEWAL_DIR}/${DOMAIN}.conf"
        fi
    fi
done

# Limpiar /csr y /keys según antigüedad
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
