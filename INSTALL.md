# Установка скомпилированного ядра на Pixel 7

Этот документ описывает процесс установки собранного GKI ядра на смартфон Pixel 7.

## ⚠️ ВАЖНО: Создайте резервную копию

Перед установкой измененного ядра создайте полную резервную копию:

```bash
# На устройстве (в режиме ADB)
adb shell
su
dd if=/dev/block/by-name/boot of=/sdcard/boot_backup.img

# Или через TWRP (если установлен)
# Меню: Backup → Select: Boot → Swipe to backup
```

---

## 📋 Требования

### На ПК
- `fastboot` (из Android Platform Tools)
- Скомпилированные файлы ядра (`Image.gz` или `Image`)
- USB кабель

### На устройстве
- Pixel 7 с Android 13
- Разблокированный загрузчик (bootloader)
- Режим отладки USB включен

### Получение файлов ядра
```bash
# Скачать артефакты из GitHub Actions
# https://github.com/AllCrash/Kernelpix7/actions

# Или собрать локально
./build-gki-kernel.sh
ls kernel-build/output/Image*
```

---

## 🔓 Разблокировка загрузчика (bootloader)

Если загрузчик еще не разблокирован:

```bash
# 1. Подключить устройство
adb devices

# 2. Загрузить в режим Fastboot
adb reboot bootloader

# 3. Разблокировать загрузчик
fastboot flashing unlock

# 4. Подтвердить на устройстве (Volume Up)
# 5. Перезагрузить
fastboot reboot
```

⚠️ **Внимание:** Разблокировка загрузчика сотрет все данные!

---

## 📥 Способ 1: Через fastboot (Рекомендуется)

### Подготовка

```bash
# 1. Извлечь файлы ядра из артефактов
unzip gki-kernel-pixel7.zip
cd kernel-build/output

# 2. Проверить наличие файлов
ls -la Image*
```

### Загрузка в режим Fastboot

```bash
# Способ 1: Через adb (если устройство включено)
adb reboot bootloader

# Способ 2: Вручную
# 1. Выключить устройство
# 2. Зажать Power + Volume Down до появления меню загрузчика
# 3. Нажать Volume Down до выделения "Fastboot Mode"
# 4. Нажать Power для выбора
```

### Установка ядра

```bash
# Вариант A: Используя Image.gz (рекомендуется)
fastboot flash boot Image.gz

# Вариант B: Используя Image (несжатое)
fastboot flash boot Image

# Вариант C: Используя boot.img (если есть)
fastboot flash boot boot.img
```

### Проверка

```bash
# Вывести информацию о partition
fastboot getvar all | grep boot

# Перезагрузить устройство
fastboot reboot

# На экране должно появиться: Fastboot Mode Complete
```

---

## 📥 Способ 2: Через TWRP Recovery

Требуется установленное кастомное восстановление (TWRP, OrangeFox и т.д.)

### Создание boot.img

```bash
# На ПК: Использовать Image как boot.img
cp Image boot.img

# Или создать boot.img с помощью mkbootimg
mkbootimg \
  --kernel Image \
  --ramdisk ramdisk.cpio.gz \
  --cmdline "..." \
  -o boot.img
```

### Установка через TWRP

```bash
# 1. Загрузить устройство в TWRP
adb reboot recovery

# 2. В TWRP меню выбрать
# → Install → Выбрать boot.img
# → Swipe to confirm flash

# 3. Перезагрузить
# → Reboot System
```

---

## 📥 Способ 3: Через ADB (только для разработчиков)

```bash
# Требуется аккесс root (KernelSU)

# 1. Передать файл на устройство
adb push Image /sdcard/boot.img

# 2. Подключиться к shell
adb shell

# 3. От root'а
su

# 4. Написать ядро в partition
dd if=/sdcard/boot.img of=/dev/block/by-name/boot

# 5. Перезагрузить
reboot
```

⚠️ **Опасно:** Неправильное использование `dd` может затвердеть устройство!

---

## ✅ Проверка установки

### На устройстве

```bash
# 1. Загрузиться в новое ядро
# 2. Открыть Settings → About Phone

# Проверить версию ядра
adb shell cat /proc/version

# Должно содержать:
# - Linux version 5.10.xxx
# - android-build (наша маскировка)
# - google.com (наша маскировка)
```

### Проверка Kprobes

```bash
# На устройстве (с root через KernelSU)
adb shell

su

# Проверить Kprobes
cat /sys/kernel/debug/kprobes/blacklist
# Должен быть список доступных для трассировки символов

# Проверить ftrace
cat /sys/kernel/debug/tracing/available_tracers
# Должно содержать: kprobes tracepoints ...
```

### Проверка SuSFS

```bash
# На устройстве (с root)
su

# SuSFS должна быть загружена в KernelSU
# Проверить логи KernelSU
cat /proc/kmsg | grep -i susfs
```

### Проверка Metadata Masking

```bash
# На ПК: Вывести информацию о компиляции
adb shell cat /proc/version

# Должно быть:
# Compiler: clang
# Compiled by: android-build
# Compiled on: google.com (вместо хоста GitHub Actions)
```

---

## 🔄 Откат к оригинальному ядру

### Способ 1: Через fastboot

```bash
# 1. Загрузить официальное ядро со своего телефона или с Google servers

# 2. Загрузить в режим Fastboot
adb reboot bootloader

# 3. Прошить оригинальное ядро
fastboot flash boot original_boot.img

# 4. Перезагрузить
fastboot reboot
```

### Способ 2: Через ранее сохраненную резервную копию

```bash
# Использовать boot_backup.img (созданный перед установкой)
adb reboot bootloader
fastboot flash boot boot_backup.img
fastboot reboot
```

### Способ 3: Полное восстановление прошивки

```bash
# Скачать оригинальную прошивку Android 13 для Pixel 7 с сайта Google:
# https://developers.google.com/android/images

# Распаковать архив
unzip bluejay-user-13-TQ3A.200505.003-release-keys.zip

# Запустить скрипт восстановления
bash flash-all.sh

# Устройство полностью восстановлено в оригинальное состояние
```

---

## 🆘 Troubleshooting

### Проблема: "fastboot not recognized"

```bash
# Установить Platform Tools
# https://developer.android.com/studio/releases/platform-tools

# Или добавить в PATH
export PATH=$PATH:~/Android/Sdk/platform-tools

fastboot --version  # Проверить
```

### Проблема: "Device not found in fastboot"

```bash
# 1. Проверить USB кабель
# 2. Включить Debug Mode на телефоне:
#    Settings → Developer Options → USB Debugging

# 3. Выполнить авторизацию
adb devices
# Подтвердить на телефоне: "Allow USB debugging"

# 4. Перезагрузить fastboot
adb reboot bootloader
```

### Проблема: "Bootloader is locked"

```bash
# Разблокировать bootloader
adb reboot bootloader
fastboot flashing unlock
# Подтвердить Volume Up на устройстве
```

### Проблема: Устройство не загружается

```bash
# 1. Зажать Power + Volume Down до меню bootloader
# 2. Выбрать "Recovery"
# 3. Используя TWRP или стоковое восстановление, вернуть старое ядро
# 4. Перезагрузить

# Или использовать fastboot:
adb reboot bootloader
fastboot flash boot boot_backup.img
fastboot reboot
```

### Проблема: "Invalid sparse data format"

```bash
# Image.gz может быть закодирован как sparse data
# Решение: использовать Image вместо Image.gz

# Или распаковать архив
gunzip Image.gz  # Получится Image файл
fastboot flash boot Image
```

---

## 📊 Проверка успеха

### До установки

```bash
# Оригинальное ядро
adb shell cat /proc/version
# Пример: Linux version 5.10.xxx google-build (Google)
```

### После установки

```bash
# Новое ядро с нашими модификациями
adb shell cat /proc/version
# Пример: Linux version 5.10.xxx android-build (google.com)
#         [KernelSU] [SuSFS] [Kprobes enabled]
```

---

## 🔒 Безопасность

### Точки риска
1. **Разблокировка bootloader** — может перехватить вредоносный код
2. **Custom kernel** — может содержать уязвимости
3. **Root доступ** — полный контроль над устройством

### Рекомендации
- ✅ Используйте только проверенные исходники
- ✅ Проверяйте SHA256 хешей загруженных файлов
- ✅ Не предоставляйте root неизвестным приложениям
- ✅ Регулярно обновляйте компоненты (KernelSU, SuSFS)
- ✅ Тестируйте в виртуальной машине перед установкой

---

## 📝 Лог установки (пример)

```bash
$ adb reboot bootloader
$ fastboot flash boot Image.gz
Sending 'boot' (4096 KB)                           OKAY [  0.123s]
Writing 'boot'                                      OKAY [  0.456s]
Finished. Total time: 0.579s

$ fastboot reboot
Rebooting                                           OKAY [  0.002s]
Finished. Total time: 0.002s

$ adb shell cat /proc/version
Linux version 5.10.198-android-build (android-build@google.com) 
(aarch64-linux-android-gcc (GCC) 9.3.0, GNU ld (GNU Binutils) 2.34.0) 
#1 SMP PREEMPT Thu, 09 Jun 2026 21:45:00 UTC

✅ Ядро успешно установлено!
```

---

## 🔗 Дополнительные ресурсы

- [Fastboot Manual](https://developer.android.com/studio/releases/platform-tools)
- [Google Pixel Documentation](https://support.google.com/pixelphone)
- [KernelSU Documentation](https://kernelsu.org)
- [TWRP Recovery](https://twrp.me)

---

**Дата обновления:** June 9, 2026  
**Совместимость:** Pixel 7, Android 13  
**Метод:** fastboot / TWRP / ADB
