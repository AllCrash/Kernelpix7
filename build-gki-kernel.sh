#!/bin/bash

################################################################################
# GKI Kernel Build Script для Android 13 (Pixel 7 / panther)
# Версия: 2.0 - Полная сборка с компиляцией
# 
# Назначение: Автоматическая сборка GKI ядра 5.10 с интеграцией:
#   - KernelSU Next
#   - SuSFS v1.5.7
#   - Полная поддержка Kprobes
#   - Маскировка метаданных сборки
################################################################################

set -euo pipefail

# ЦВЕТА
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ПЕРЕМЕННЫЕ ОКРУЖЕНИЯ
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/kernel-build"
KERNEL_SOURCE="${WORK_DIR}/kernel"
BUILD_OUTPUT="${WORK_DIR}/output"

# ПАРАМЕТРЫ ЯДРА
ANDROID_BRANCH="common-android13-5.10"
BUILD_CONFIG="common/build.config.gki.aarch64"

# TOOLCHAIN
export CROSS_COMPILE="aarch64-linux-android-"
export CROSS_COMPILE_COMPAT="arm-linux-gnueabihf-"
export LINUX_COMPILE_BY="android-build"
export LINUX_COMPILE_HOST="google.com"

# ФУНКЦИИ
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $*"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*"
}

error_exit() {
    log_error "$1"
    exit 1
}

# ПРОВЕРКА ЗАВИСИМОСТЕЙ
verify_dependencies() {
    log_info "Проверка зависимостей..."
    
    local required_cmds=("git" "curl" "unzip" "patch" "make" "gcc" "clang")
    
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_warn "Команда '$cmd' не найдена"
        fi
    done
    
    log_success "Проверка завершена"
}

# ПОДГОТОВКА ДИРЕКТОРИЙ
prepare_directories() {
    log_info "Подготовка директорий..."
    
    mkdir -p "$WORK_DIR" "$KERNEL_SOURCE" "$BUILD_OUTPUT"
    
    log_success "Директории готовы"
}

# СИНХРОНИЗАЦИЯ ИСХОДНИКОВ
sync_gki_sources() {
    log_info "Синхронизация GKI исходников (branch: $ANDROID_BRANCH)..."
    
    cd "$WORK_DIR"
    
    if [ ! -d "$KERNEL_SOURCE/.git" ]; then
        log_info "Клонирование ядра от Google..."
        git clone --depth 1 \
                  --branch "$ANDROID_BRANCH" \
                  https://android.googlesource.com/kernel/common \
                  kernel || error_exit "Ошибка клонирования ядра"
    else
        log_info "Обновление существующего репозитория..."
        cd "$KERNEL_SOURCE"
        git fetch --depth 1 origin "$ANDROID_BRANCH"
        git checkout FETCH_HEAD
    fi
    
    log_success "Исходники синхронизированы"
}

# ИНТЕГРАЦИЯ KERNELSU
integrate_kernelsu_next() {
    log_info "Интеграция KernelSU Next..."
    
    local kernelsu_dir="${KERNEL_SOURCE}/drivers/kernelsu"
    
    [ -d "$kernelsu_dir" ] && rm -rf "$kernelsu_dir"
    
    git clone --depth 1 https://github.com/KernelSU-Next/KernelSU-Next "$kernelsu_dir" || \
        error_exit "Ошибка клонирования KernelSU Next"
    
    # Применение встроенных патчей
    if [ -d "${kernelsu_dir}/patches" ]; then
        cd "$KERNEL_SOURCE"
        for patch_file in "${kernelsu_dir}"/patches/*.patch; do
            if [ -f "$patch_file" ]; then
                log_info "Применение: $(basename "$patch_file")"
                patch -p1 < "$patch_file" || log_warn "Конфликт в $(basename "$patch_file")"
            fi
        done
    fi
    
    log_success "KernelSU Next интегрирована"
}

# ИНТЕГРАЦИЯ SUSFS
integrate_susfs() {
    log_info "Интеграция SuSFS..."
    
    local susfs_dir="${WORK_DIR}/susfs-extract"
    mkdir -p "$susfs_dir"
    
    cd "$susfs_dir"
    
    log_info "Загрузка SuSFS архива..."
    curl -L -o susfs.zip \
         "https://github.com/coderfan1/susfs4ksu/archive/refs/heads/main.zip" || \
        error_exit "Ошибка загрузки SuSFS"
    
    unzip -q susfs.zip
    
    local susfs_src=$(find . -maxdepth 1 -type d -name "susfs*" | head -1)
    
    if [ -z "$susfs_src" ]; then
        error_exit "Директория SuSFS не найдена"
    fi
    
    # Копирование файлов в KernelSU
    local kernelsu_dir="${KERNEL_SOURCE}/drivers/kernelsu"
    
    [ -f "$susfs_src/susfs.c" ] && cp "$susfs_src/susfs.c" "$kernelsu_dir/"
    [ -f "$susfs_src/susfs.h" ] && cp "$susfs_src/susfs.h" "$kernelsu_dir/"
    
    # Применение патчей
    cd "$KERNEL_SOURCE"
    for patch_file in "$susfs_src"/patches/*.patch; do
        if [ -f "$patch_file" ]; then
            log_info "Применение: $(basename "$patch_file")"
            patch -p0 < "$patch_file" 2>/dev/null || \
            patch -p1 < "$patch_file" 2>/dev/null || \
            log_warn "Патч не применен"
        fi
    done
    
    log_success "SuSFS интегрирована"
}

# КОНФИГУРАЦИЯ ЯДРА
configure_kernel() {
    log_info "Конфигурирование опций ядра..."
    
    cd "$KERNEL_SOURCE"
    
    local defconfig="arch/arm64/configs/gki_defconfig"
    
    if [ ! -f "$defconfig" ]; then
        error_exit "gki_defconfig не найден"
    fi
    
    # Backup
    cp "$defconfig" "${defconfig}.bak"
    
    # Kprobes
    for opt in "CONFIG_KPROBES=y" "CONFIG_KPROBE_EVENTS=y"; do
        key="${opt%%=*}"
        sed -i "/^${key}/d" "$defconfig"
        echo "$opt" >> "$defconfig"
    done
    
    # SuSFS
    echo "CONFIG_SUSFS=y" >> "$defconfig"
    
    log_success "Конфигурация завершена"
}

# ОСНОВНАЯ КОМПИЛЯЦИЯ
build_kernel() {
    log_info "Начало компиляции ядра..."
    
    cd "$KERNEL_SOURCE"
    
    if [ ! -f "build/build.sh" ]; then
        error_exit "build/build.sh не найден"
    fi
    
    # Запуск официального скрипта сборки
    log_info "Запуск build/build.sh с параметрами..."
    
    bash build/build.sh 2>&1 | tee "${WORK_DIR}/build.log" || \
        error_exit "Ошибка при компиляции ядра"
    
    log_success "Компиляция успешна"
}

# СБОР АРТЕФАКТОВ
collect_artifacts() {
    log_info "Сбор артефактов..."
    
    cd "$KERNEL_SOURCE"
    
    # Поиск выходных файлов
    local kernel_image=""
    
    if [ -f "arch/arm64/boot/Image.gz" ]; then
        cp "arch/arm64/boot/Image.gz" "$BUILD_OUTPUT/"
        kernel_image="arch/arm64/boot/Image.gz"
        log_success "Скопирован Image.gz"
    fi
    
    if [ -f "arch/arm64/boot/Image" ]; then
        cp "arch/arm64/boot/Image" "$BUILD_OUTPUT/"
        log_success "Скопирован Image"
    fi
    
    # Конфиг
    [ -f "arch/arm64/configs/gki_defconfig" ] && \
        cp "arch/arm64/configs/gki_defconfig" "$BUILD_OUTPUT/"
    
    # Модули
    if [ -d "out/android13-5.10/dist/lib/modules" ]; then
        cp -r "out/android13-5.10/dist/lib/modules" "$BUILD_OUTPUT/"
        log_success "Скопированы модули"
    fi
    
    if [ -z "$kernel_image" ]; then
        log_warn "Ядро не найдено в стандартных путях"
        find "$KERNEL_SOURCE/out" -name "Image*" -type f 2>/dev/null | while read f; do
            cp "$f" "$BUILD_OUTPUT/" && log_info "Найдено: $(basename "$f")"
        done
    fi
    
    log_info "Артефакты в: $BUILD_OUTPUT"
    ls -lah "$BUILD_OUTPUT"
}

# ГЛАВНАЯ ФУНКЦИЯ
main() {
    log_info "================================"
    log_info "GKI Kernel Build для Pixel 7"
    log_info "================================"
    
    verify_dependencies
    prepare_directories
    
    log_info "ЭТАП 1: Синхронизация исходников"
    sync_gki_sources
    
    log_info "ЭТАП 2: Интеграция KernelSU Next"
    integrate_kernelsu_next
    
    log_info "ЭТАП 3: Интеграция SuSFS"
    integrate_susfs
    
    log_info "ЭТАП 4: Конфигурация ядра"
    configure_kernel
    
    log_info "ЭТАП 5: Компиляция ядра"
    build_kernel
    
    log_info "ЭТАП 6: Сбор артефактов"
    collect_artifacts
    
    log_success "================================"
    log_success "Сборка завершена успешно!"
    log_success "Выход: $BUILD_OUTPUT"
    log_success "================================"
}

# ТОЧКА ВХОДА
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
