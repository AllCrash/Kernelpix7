# GKI Kernel Build для Pixel 7 (Android 13)

[![Build GKI Kernel](https://github.com/AllCrash/Kernelpix7/actions/workflows/build-kernel.yml/badge.svg)](https://github.com/AllCrash/Kernelpix7/actions)

**Полнофункциональная сборка Generic Kernel Image (GKI) версии 5.10 для смартфона Pixel 7 (panther, aarch64) с интегрированным скрытым рут-доступом, маскировкой рут-процессов и низкоуровневой трассировкой.**

## 📋 Содержание

- [Особенности](#-особенности)
- [Требования](#-требования)
- [Быстрый старт](#-быстрый-старт)
- [Архитектура сборки](#-архитектура-сборки)
- [Компоненты](#-интегрированные-компоненты)
- [Использование](#-использование)
- [GitHub Actions](#-github-actions)
- [Troubleshooting](#-troubleshooting)

---

## ✨ Особенности

### 🔒 Безопасность и приватность
- **KernelSU Next** — скрытый рут-доступ (не видим для приложений)
- **SuSFS v1.5.7** — маскировка рут-процессов и кастомных модулей
- **Маскировка метаданных** — скрытие информации о хосте и компиляции

### 🔧 Функциональность
- **Kprobes** — полная поддержка динамической трассировки ядра
- **CONFIG_KPROBES=y** — динамические точки останова в ядре
- **CONFIG_KPROBE_EVENTS=y** — трассировка событий через ftrace
- **CONFIG_HAVE_KPROBES=y** — архитектурная поддержка

### ⚙️ Надежность
- **Отказоустойчивый скрипт** — обработка ошибок на каждом этапе
- **Shallow clone** — ускоренная загрузка исходников (depth=1)
- **Batch patching** — автоматический пропуск конфликтов патчей
- **Кэширование** — использование ccache для ускорения повторных сборок

---

## 📦 Требования

### Локальная сборка
```bash
# ОС: Ubuntu 20.04+ / Debian 11+
# Минимум 50 GB свободного места
# Минимум 8 GB RAM (рекомендуется 16+ GB)
# Минимум 4 CPU ядра

# Зависимости:
sudo apt-get install -y \
  build-essential git curl unzip python3 libssl-dev \
  bc bison flex libelf-dev ccache repo wget
```

### GitHub Actions
- ✅ Встроенная поддержка (ubuntu-latest)
- ✅ 6 часов лимит на сборку (достаточно)
- ✅ Автоматическая загрузка NDK

---

## 🚀 Быстрый старт

### Локальная сборка

```bash
# 1. Клонируем репозиторий
git clone https://github.com/AllCrash/Kernelpix7.git
cd Kernelpix7

# 2. Делаем скрипт исполняемым
chmod +x build-gki-kernel.sh

# 3. Запускаем сборку
./build-gki-kernel.sh

# 4. Результаты в kernel-build/output/
ls -lah kernel-build/output/
```

### GitHub Actions

```bash
# Сборка автоматически запускается на:
# - Push в ветку main или develop
# - Pull Request в main
# - Manual trigger (Actions → Build GKI Kernel → Run workflow)

# Артефакты доступны в:
# Actions → Build Summary → gki-kernel-pixel7
```

---

## 🏗️ Архитектура сборки

### Этап 1: Синхронизация исходников
```bash
↓
Google GKI Repository (common-android13-5.10)
↓
kernel-build/kernel/ (Shallow clone, depth=1)
```
- Ветка: `common-android13-5.10`
- Глубина: 1 (только актуальный коммит)
- Время: ~5-10 минут

### Этап 2: Интеграция KernelSU Next
```bash
↓
KernelSU-Next/KernelSU-Next (GitHub)
↓
drivers/kernelsu/ (в исходниках ядра)
↓
Применение встроенных патчей
```
- Клонируем последнюю версию
- Применяем патчи автоматически
- Время: ~1-2 минуты

### Этап 3: Интеграция SuSFS
```bash
↓
SuSFS Archive (curl + unzip, БЕЗ git clone)
↓
susfs.c / susfs.h → drivers/kernelsu/
↓
Применение патчей (--batch режим)
↓
Интеграция в KernelSU Makefile
```
- Загрузка архива через curl
- Автоматический пропуск конфликтов
- Добавление susfs.o в систему сборки
- Время: ~2-3 минуты

### Этап 4: Конфигурация опций
```bash
↓
arch/arm64/configs/gki_defconfig
↓
+ CONFIG_KPROBES=y
+ CONFIG_HAVE_KPROBES=y
+ CONFIG_KPROBE_EVENTS=y
+ CONFIG_SUSFS=y
```
- Добавляем опции динамической трассировки
- Добавляем поддержку SuSFS
- Резервная копия оригинального дефконфига
- Время: <1 минуты

### Этап 5: Патчирование конфигов сборки
```bash
↓
common/build.config.gki.aarch64
↓
POST_DEFCONFIG_CMDS="" (отключаем check_defconfig)
```
- Отключаем Google check (видит нестандартные параметры)
- Позволяет компилировать с кастомными CONFIG опциями
- Время: <1 минуты

### Этап 6: Маскировка метаданных
```bash
↓
scripts/mkcompile_h
↓
export LINUX_COMPILE_BY="android-build"
export LINUX_COMPILE_HOST="google.com"
```
- Скрывает информацию о GitHub Actions хосте
- Устанавливает стандартные значения Google
- Время: <1 минуты

### Этап 7: Компиляция ядра
```bash
↓
build/build.sh
↓
CROSS_COMPILE=aarch64-linux-android-
CROSS_COMPILE_COMPAT=arm-linux-gnueabihf-
↓
arch/arm64/boot/Image.gz
↓
modules/ (если включены)
```
- Главный процесс сборки (~3-4 часа на CI/CD)
- Использует NDK r23c для кросскомпиляции
- Параллельная компиляция (4+ потока)
- Время: ~180-240 минут

### Этап 8: Сбор артефактов
```bash
↓
kernel-build/output/
├── Image.gz (сжатое ядро)
├── Image (разжатое ядро)
├── gki_defconfig (финальная конфигурация)
└── modules/ (если есть)
```
- Копируем скомпилированные файлы
- Сохраняем финальную конфигурацию
- Время: <1 минуты

---

## 🧩 Интегрированные компоненты

### 1. KernelSU Next
**Назначение:** Скрытый рут-доступ, не видимый приложениям

```
Репозиторий: https://github.com/KernelSU-Next/KernelSU-Next
Расположение: drivers/kernelsu/
Версия: Latest (master)
Функции:
  - Скрытое управление правами доступа
  - Интеграция с Magisk политиками
  - Изоляция рут-процессов от системы
```

### 2. SuSFS v1.5.7
**Назначение:** Маскировка рут-процессов и кастомных модулей

```
Источник: https://github.com/coderfan1/susfs4ksu
Метод загрузки: curl + unzip (БЕЗ git clone)
Файлы:
  - susfs.c (реализация)
  - susfs.h (заголовки)
Патчи: Автоматически применяются к ядру и KernelSU
Функции:
  - Скрытие файлов и процессов
  - Фильтрация системных вызовов
  - Защита от обнаружения модификаций
```

### 3. Kprobes (CONFIG_KPROBES=y)
**Назначение:** Динамическая трассировка ядра без перекомпиляции

```
CONFIG_KPROBES=y           - Основная поддержка динамических точек
CONFIG_HAVE_KPROBES=y      - Архитектурная поддержка (aarch64)
CONFIG_KPROBE_EVENTS=y     - Интеграция с ftrace/perf

Использование:
  echo 'p:myprobe sys_openat' > /sys/kernel/debug/tracing/kprobe_events
  cat /sys/kernel/debug/tracing/trace

Инструменты:
  - kprobes (низкоуровневая трассировка)
  - ftrace (высокоуровневая трассировка)
  - perf (анализ производительности)
```

### 4. Маскировка метаданных
**Назначение:** Скрытие информации о компиляции

```
Модифицируемые переменные:
  LINUX_COMPILE_BY: "android-build"  (вместо GitHub Actions runner ID)
  LINUX_COMPILE_HOST: "google.com"   (вместо IP адреса виртуальной машины)

Это изменяется в:
  - scripts/mkcompile_h
  - Экспортируется в окружении сборки

Проверка в готовом ядре:
  strings vmlinux | grep "Compiler:"
  strings vmlinux | grep "Compiled"
```

---

## 💻 Использование

### Локально

```bash
# Минимальная сборка (только обязательное)
./build-gki-kernel.sh

# С отладкой (сохранит больше логов)
bash -x ./build-gki-kernel.sh 2>&1 | tee full-build.log

# Только проверка зависимостей
bash -c 'source build-gki-kernel.sh; verify_dependencies'
```

### GitHub Actions

#### Автоматическая сборка
```bash
# Просто push в main или develop
git push origin main

# Workflow запустится автоматически
# Статус: Actions tab → Latest run
```

#### Ручной запуск
1. Перейти на вкладку **Actions**
2. Выбрать **Build GKI Kernel**
3. Нажать **Run workflow**
4. Дождаться завершения

#### Скачивание артефактов
1. В Actions найти завершенный workflow
2. В Build Summary разделе нажать на **gki-kernel-pixel7**
3. Скачать ZIP архив

---

## 🔄 GitHub Actions

### Конфигурация

```yaml
# Triggers (когда запускается):
on:
  push:
    branches: [main, develop]    # На любой push
  pull_request:
    branches: [main]              # На PR
  workflow_dispatch:              # Ручной запуск

# Ограничения:
timeout-minutes: 360   # 6 часов
runs-on: ubuntu-latest # Последний Ubuntu
```

### Этапы workflow

| Этап | Время | Описание |
|------|-------|---------|
| Checkout | ~10s | Клонирование репозитория |
| Dependencies | ~2m | Установка зависимостей |
| Android NDK | ~3m | Загрузка и настройка NDK r23c |
| Clang Setup | ~1m | Конфигурация компилятора |
| ccache | ~30s | Настройка кэширования |
| **Build Kernel** | **~180-240m** | Основная сборка |
| Verification | ~2m | Проверка артефактов |
| Report | ~1m | Генерация отчета |
| Upload | ~5m | Загрузка результатов |

**Итого:** ~200-250 минут (~3-4 часа)

### Артефакты

Доступны 30 дней в Actions:
- `kernel-build/output/Image.gz` — сжатое ядро
- `kernel-build/output/Image` — разжатое ядро
- `kernel-build/output/gki_defconfig` — конфигурация
- `BUILD_REPORT.md` — отчет о сборке
- `build.log` — полный лог компиляции

---

## 📊 Результаты

### Успешная сборка
```
✅ BUILD SUCCESSFUL

Файлы в kernel-build/output/:
-rw-r--r-- 1 ... 15M Jun  9 21:45 Image
-rw-r--r-- 1 ...  5M Jun  9 21:45 Image.gz
-rw-r--r-- 1 ... 512K Jun  9 21:45 gki_defconfig
```

### Проверка конфигурации
```bash
# Kprobes включены?
grep CONFIG_KPROBE kernel-build/output/gki_defconfig

CONFIG_KPROBES=y
CONFIG_HAVE_KPROBES=y
CONFIG_KPROBE_EVENTS=y

# SuSFS включена?
grep CONFIG_SUSFS kernel-build/output/gki_defconfig

CONFIG_SUSFS=y

# Метаданные замаскированы?
strings kernel-build/output/Image | grep "Compiler"
```

---

## 🆘 Troubleshooting

### Ошибка: "repo tool not found"
```bash
# Решение: Установить repo
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod +x ~/bin/repo
export PATH=$HOME/bin:$PATH
```

### Ошибка: "Kernel image not found"
```bash
# Проверить: есть ли Image.gz в arch/arm64/boot/
ls -la kernel-build/kernel/arch/arm64/boot/

# Если нет — сборка не завершилась успешно
tail -100 build.log  # Проверить логи ошибок
```

### Ошибка: "Android NDK not found"
```bash
# GitHub Actions автоматически загружает NDK
# Локально: скачать с https://developer.android.com/ndk/downloads

NDK_DIR=~/android-ndk-r23c
export PATH=$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH
```

### Ошибка: "Patch failed"
```bash
# Нормально — скрипт использует --batch режим
# Конфликты автоматически пропускаются
# Проверить: важные функции скомпилировались (check build.log)
```

### Запуск не удается (permission denied)
```bash
chmod +x build-gki-kernel.sh
./build-gki-kernel.sh  # Теперь работает
```

---

## 📝 Лицензия

MIT License — Свободно используйте в личных целях

---

## 🔗 Полезные ссылки

- **KernelSU Next**: https://github.com/KernelSU-Next/KernelSU-Next
- **SuSFS**: https://github.com/coderfan1/susfs4ksu
- **Android GKI**: https://android.googlesource.com/kernel/manifest
- **Pixel 7 Board**: https://github.com/google/device-panther

---

## 📞 Поддержка

Если у вас возникла проблема:
1. Проверьте **Troubleshooting** раздел выше
2. Посмотрите **build.log** для подробностей
3. Откройте **Issue** с логами ошибок

---

**Последнее обновление:** June 9, 2026  
**Версия скрипта:** 1.0  
**Поддерживаемый kernel:** 5.10 (common-android13-5.10)  
**Целевое устройство:** Pixel 7 (panther, aarch64)
