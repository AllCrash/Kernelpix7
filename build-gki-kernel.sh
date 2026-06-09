#!/bin/bash

################################################################################
# GKI Kernel Build Script для Android 13 (Pixel 7 / panther)
# Версия: 1.0
# 
# Назначение: Автоматическая сборка чистого GKI ядра 5.10 с интеграцией:
#   - KernelSU Next (актуальная версия)
#   - SuSFS v1.5.7 (маскировка рут-процессов и модулей)
#   - Полная поддержка Kprobes для низкоуровневой трассировки
#   - Маскировка метаданных сборки (компилятор, хост)
#
# Требования: curl, unzip, git, repo tool, Android NDK/Toolchain
################################################################################

set -euo pipefail

# =============================================================================
# КОНФИГУРАЦИЯ
# =============================================================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Переменные окружения
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/kernel-build"
KERNEL_SOURCE="${WORK_DIR}/kernel"
KERNELSU_NEXT_REPO="https://github.com/KernelSU-Next/KernelSU-Next"
KERNELSU_NEXT_VERSION="latest"
SUSFS_ARCHIVE_URL="https://github.com/coderfan1/susfs4ksu/archive/refs/heads/main.zip"
SUSFS_EXTRACT_DIR="${WORK_DIR}/susfs-extract"

# Параметры сборки
ANDROID_BRANCH="common-android13-5.10"
ANDROID_DEPTH=1
BUILD_CONFIG="common/build.config.gki.aarch64"
DEVICE_NAME="panther"
ANDROID_VERSION=13

# Маскировка метаданных
LINUX_COMPILE_BY="android-build"
LINUX_COMPILE_HOST="google.com"

# =============================================================================
# ФУНКЦИИ ЛОГИРОВАНИЯ И ОБРАБОТКИ ОШИБОК
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

error_exit() {
    log_error "$1"
    exit 1
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        error_exit "Команда '$1' не найдена. Пожалуйста, установите '$1'."
    fi
}

# =============================================================================
# ПРОВЕРКА ЗАВИСИМОСТЕЙ
# =============================================================================

verify_dependencies() {
    log_info "Проверка зависимостей..."
    
    check_command "git"
    check_command "curl"
    check_command "unzip"
    check_command "patch"
    check_command "find"
    check_command "sed"
    
    if [ -z "${CI:-}" ]; then
        check_command "repo" || log_warn "repo tool не найден"
    fi
    
    log_success "Все зависимости проверены"
}

# =============================================================================
# ИНИЦИАЛИЗАЦИЯ И ПОДГОТОВКА ДИРЕКТОРИЙ
# =============================================================================

prepare_directories() {
    log_info "Подготовка директорий сборки..."
    
    mkdir -p "$WORK_DIR"
    mkdir -p "$KERNEL_SOURCE"
    mkdir -p "$SUSFS_EXTRACT_DIR"
    
    cd "$WORK_DIR"
    log_success "Директории готовы: $WORK_DIR"
}

# =============================================================================
# ЭТАП 1: СИНХРОНИЗАЦИЯ ИСХОДНИКОВ GOOGLE GKI
# =============================================================================

sync_gki_sources() {
    log_info "Синхронизация исходников Google GKI (branch: $ANDROID_BRANCH)..."
    
    cd "$WORK_DIR"
    
    if command -v repo &> /dev/null; then
        log_info "Использование repo tool для синхронизации..."
        
        if [ ! -d ".repo" ]; then
            repo init -u https://android.googlesource.com/kernel/manifest \
                     -b "$ANDROID_BRANCH" \
                     --depth="$ANDROID_DEPTH" \
                     -m default.xml || error_exit "Ошибка инициализации repo"
        fi
        
        repo sync -c --no-tags --depth="$ANDROID_DEPTH" -j 4 || \
            error_exit "Ошибка синхронизации через repo"
    else
        log_warn "repo tool недоступен; используется git..."
        
        git clone --depth "$ANDROID_DEPTH" \
                  --branch "$ANDROID_BRANCH" \
                  https://android.googlesource.com/kernel/common \
                  kernel || error_exit "Ошибка клонирования ядра"
    fi
    
    log_success "Исходники GKI синхронизированы"
}

# =============================================================================
# ЭТАП 2: ИНТЕГРАЦИЯ KERNELSU NEXT
# =============================================================================

integrate_kernelsu_next() {
    log_info "Интеграция KernelSU Next..."
    
    local kernelsu_dir="${KERNEL_SOURCE}/drivers/kernelsu"
    
    if [ -d "$kernelsu_dir" ]; then
        log_warn "Директория KernelSU уже существует; удаление..."
        rm -rf "$kernelsu_dir"
    fi
    
    log_info "Клонирование репозитория KernelSU Next..."
    git clone --depth 1 "$KERNELSU_NEXT_REPO" "$kernelsu_dir" || \
        error_exit "Ошибка клонирования KernelSU Next"
    
    if [ -d "${kernelsu_dir}/patches" ]; then
        log_info "Применение встроенных патчей KernelSU..."
        cd "$KERNEL_SOURCE"
        
        for patch_file in "${kernelsu_dir}"/patches/*.patch; do
            if [ -f "$patch_file" ]; then
                log_info "Применение патча: $(basename "$patch_file")"
                patch --batch -p1 < "$patch_file" || \
                    log_warn "Конфликт при применении $(basename "$patch_file")"
            fi
        done
    fi
    
    log_success "KernelSU Next интегрирована"
}

# =============================================================================
# ЭТАП 3: ЗАГРУЗКА И ИНТЕГРАЦИЯ SUSFS
# =============================================================================

download_and_integrate_susfs() {
    log_info "Загрузка архива SuSFS v1.5.7..."
    
    cd "$SUSFS_EXTRACT_DIR"
    
    log_info "Скачивание SuSFS архива через curl..."
    if ! curl -L -f -o susfs-archive.zip "$SUSFS_ARCHIVE_URL"; then
        error_exit "Ошибка загрузки архива SuSFS"
    fi
    
    log_info "Распаковка архива..."
    if ! unzip -q susfs-archive.zip; then
        error_exit "Ошибка распаковки архива SuSFS"
    fi
    
    local susfs_src_dir=$(find "$SUSFS_EXTRACT_DIR" -maxdepth 2 -type d -name "susfs4ksu*" | head -1)
    
    if [ -z "$susfs_src_dir" ]; then
        error_exit "Не удалось найти директорию susfs в архиве"
    fi
    
    log_info "Найдена директория SuSFS: $susfs_src_dir"
    
    local kernelsu_driver_dir="${KERNEL_SOURCE}/drivers/kernelsu"
    
    log_info "Копирование файлов SuSFS..."
    
    if [ -f "${susfs_src_dir}/susfs.c" ]; then
        cp "${susfs_src_dir}/susfs.c" "${kernelsu_driver_dir}/" || \
            error_exit "Ошибка копирования susfs.c"
        log_success "Скопирован susfs.c"
    fi
    
    if [ -f "${susfs_src_dir}/susfs.h" ]; then
        cp "${susfs_src_dir}/susfs.h" "${kernelsu_driver_dir}/" || \
            error_exit "Ошибка копирования susfs.h"
        log_success "Скопирован susfs.h"
    fi
    
    log_info "Применение патчей SuSFS..."
    
    cd "$KERNEL_SOURCE"
    
    for patch_file in "${susfs_src_dir}"/patches/*.patch "${susfs_src_dir}"/*.patch; do
        if [ -f "$patch_file" ]; then
            log_info "Применение патча: $(basename "$patch_file")"
            if ! patch --batch -p0 < "$patch_file" 2>/dev/null; then
                if ! patch --batch -p1 < "$patch_file" 2>/dev/null; then
                    log_warn "Патч $(basename "$patch_file") не применен"
                fi
            fi
        fi
    done
    
    local kernelsu_makefile="${kernelsu_driver_dir}/Makefile"
    if [ -f "$kernelsu_makefile" ]; then
        if ! grep -q "susfs\.o" "$kernelsu_makefile"; then
            echo "obj-y += susfs.o" >> "$kernelsu_makefile"
            log_success "Добавлен susfs.o в Makefile"
        fi
    fi
    
    log_success "SuSFS интегрирована"
}

# =============================================================================
# ЭТАП 4: КОНФИГУРАЦИЯ ЯДРА (KPROBES, DEFCONFIG)
# =============================================================================

configure_kernel_options() {
    log_info "Конфигурирование опций ядра для Kprobes и SuSFS..."
    
    cd "$KERNEL_SOURCE"
    
    local gki_defconfig="arch/arm64/configs/gki_defconfig"
    
    if [ ! -f "$gki_defconfig" ]; then
        gki_defconfig=$(find "$KERNEL_SOURCE" -name "gki_defconfig" -type f | head -1)
        
        if [ -z "$gki_defconfig" ]; then
            error_exit "Не удалось найти gki_defconfig"
        fi
    fi
    
    log_info "Найден дефконфиг: $gki_defconfig"
    
    cp "$gki_defconfig" "${gki_defconfig}.bak"
    
    log_info "Добавление опций Kprobes..."
    
    for config_option in "CONFIG_KPROBES=y" "CONFIG_HAVE_KPROBES=y" "CONFIG_KPROBE_EVENTS=y"; do
        local config_key="${config_option%%=*}"
        
        sed -i "/^${config_key}/d" "$gki_defconfig"
        echo "$config_option" >> "$gki_defconfig"
        log_success "Добавлена опция: $config_option"
    done
    
    log_info "Добавление опций для SuSFS..."
    
    for config_option in "CONFIG_SUSFS=y"; do
        local config_key="${config_option%%=*}"
        
        if ! grep -q "^${config_key}" "$gki_defconfig"; then
            echo "$config_option" >> "$gki_defconfig"
            log_success "Добавлена опция: $config_option"
        fi
    done
    
    log_success "Конфигурация ядра обновлена"
}

# =============================================================================
# ЭТАП 5: МОДИФИКАЦИЯ СКРИПТОВ СБОРКИ
# =============================================================================

patch_build_config() {
    log_info "Модификация конфигурационных файлов сборки..."
    
    cd "$KERNEL_SOURCE"
    
    local build_config_file="${BUILD_CONFIG}"
    
    if [ ! -f "$build_config_file" ]; then
        error_exit "Конфигурационный файл не найден: $build_config_file"
    fi
    
    cp "$build_config_file" "${build_config_file}.bak"
    
    log_info "Отключение POST_DEFCONFIG_CMDS ��ля пропуска check_defconfig..."
    
    sed -i 's/^POST_DEFCONFIG_CMDS=.*/POST_DEFCONFIG_CMDS=""/' "$build_config_file"
    
    log_success "Конфигурационные файлы сборки модифицированы"
}

# =============================================================================
# ЭТАП 6: МАСКИРОВКА МЕТАДАННЫХ СБОРКИ
# =============================================================================

patch_compile_metadata() {
    log_info "Модификация метаданных компиляции ядра..."
    
    cd "$KERNEL_SOURCE"
    
    local mkcompile_h="scripts/mkcompile_h"
    
    if [ ! -f "$mkcompile_h" ]; then
        error_exit "Файл $mkcompile_h не найден"
    fi
    
    cp "$mkcompile_h" "${mkcompile_h}.bak"
    
    log_info "Модификация scripts/mkcompile_h..."
    
    sed -i '1a # Маскировка метаданных\nexport LINUX_COMPILE_BY="android-build"\nexport LINUX_COMPILE_HOST="google.com"' "$mkcompile_h"
    
    log_success "Метаданные сборки замаскированы"
}

# =============================================================================
# ЭТАП 7: КОМПИЛЯЦИЯ ЯДРА
# =============================================================================

build_kernel() {
    log_info "Начало компиляции ядра..."
    
    cd "$KERNEL_SOURCE"
    
    if [ ! -f "build/build.sh" ]; then
        error_exit "Скрипт build/build.sh не найден"
    fi
    
    export LINUX_COMPILE_BY="android-build"
    export LINUX_COMPILE_HOST="google.com"
    export CROSS_COMPILE="aarch64-linux-android-"
    export CROSS_COMPILE_COMPAT="arm-linux-gnueabihf-"
    
    log_info "Переменные окружения:"
    log_info "  LINUX_COMPILE_BY: $LINUX_COMPILE_BY"
    log_info "  LINUX_COMPILE_HOST: $LINUX_COMPILE_HOST"
    
    log_info "Запуск build/build.sh..."
    
    if ! bash build/build.sh; then
        error_exit "Ошибка при компиляции ядра"
    fi
    
    log_success "Компиляция ядра завершена успешно"
}

# =============================================================================
# ЭТАП 8: ПОСТОБРАБОТКА И СБОР РЕЗУЛЬТАТОВ
# =============================================================================

collect_artifacts() {
    log_info "Сбор артефактов сборки..."
    
    cd "$KERNEL_SOURCE"
    
    local output_dir="${WORK_DIR}/output"
    mkdir -p "$output_dir"
    
    if [ -f "arch/arm64/boot/Image.gz" ]; then
        cp "arch/arm64/boot/Image.gz" "$output_dir/Image.gz"
        log_success "Скопирован Image.gz"
    fi
    
    if [ -f "arch/arm64/boot/Image" ]; then
        cp "arch/arm64/boot/Image" "$output_dir/Image"
        log_success "Скопирован Image"
    fi
    
    if [ -d "modules" ]; then
        cp -r "modules" "$output_dir/"
        log_success "Скопированы модули"
    fi
    
    if [ -f "arch/arm64/configs/gki_defconfig" ]; then
        cp "arch/arm64/configs/gki_defconfig" "$output_dir/gki_defconfig"
        log_success "Скопирован gki_defconfig"
    fi
    
    log_info "Артефакты собраны в: $output_dir"
    ls -lah "$output_dir"
}

# =============================================================================
# ГЛАВНАЯ ФУНКЦИЯ ОРКЕСТРАЦИИ
# =============================================================================

main() {
    log_info "======================================"
    log_info "Сборка GKI Kernel для Pixel 7"
    log_info "Android: $ANDROID_VERSION"
    log_info "Ветка: $ANDROID_BRANCH"
    log_info "======================================"
    log_info ""
    
    log_info "Окружение сборки:"
    log_info "  OS: $(uname -s)"
    log_info "  Архитектура: $(uname -m)"
    log_info "  Рабочая директория: $WORK_DIR"
    log_info ""
    
    verify_dependencies
    prepare_directories
    
    log_info "====== ЭТАП 1: Синхронизация исходников ======"
    sync_gki_sources || error_exit "Ошибка синхронизации исходников"
    
    log_info "====== ЭТАП 2: Интеграция KernelSU Next ======"
    integrate_kernelsu_next || error_exit "Ошибка интеграции KernelSU"
    
    log_info "====== ЭТАП 3: Интеграция SuSFS ======"
    download_and_integrate_susfs || error_exit "Ошибка интеграции SuSFS"
    
    log_info "====== ЭТАП 4: Конфигурация опций ядра ======"
    configure_kernel_options || error_exit "Ошибка конфигурации"
    
    log_info "====== ЭТАП 5: Патчирование конфигов сборки ======"
    patch_build_config || error_exit "Ошибка патчирования конфигов"
    
    log_info "====== ЭТАП 6: Маскировка метаданных ======"
    patch_compile_metadata || error_exit "Ошибка маскировки метаданных"
    
    log_info "====== ЭТАП 7: Компиляция ядра ======"
    build_kernel || error_exit "Ошибка компиляции"
    
    log_info "====== ЭТАП 8: Сбор артефактов ======"
    collect_artifacts || log_warn "Некоторые артефакты не найдены"
    
    log_success ""
    log_success "======================================"
    log_success "Сборка ядра завершена успешно!"
    log_success "======================================"
    log_success "Артефакты находятся в: ${WORK_DIR}/output"
}

# =============================================================================
# ТОЧКА ВХОДА
# =============================================================================

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
