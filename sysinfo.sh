#!/usr/bin/env bash
# Выбираем интерпретатор Bash через env — это делает скрипт кроссплатформенным.


# Включаем "строгий режим"
 
set -o errexit   # Если любая команда завершается ошибкой → скрипт сразу останавливается.
set -o nounset   # Ошибка при использовании необъявленных переменных.
set -o pipefail  # Если ошибка в любой команде конвейера (pipeline), ошибка не игнорируется.

 
# Глобальные переменные
 
LOG_PATH=""        # Путь к файлу, куда будет перенаправляться stdout (опция -l, --log)
ERR_PATH=""        # Путь к файлу для ошибок stderr (опция -e, --errors)
DO_USERS=0         # Флаг: выводить ли пользователей (опция -u, --users)
DO_PROCESSES=0     # Флаг: выводить ли процессы (опция -p, --processes)

 
# Функция: вывод справки
 
print_help() {
    cat <<EOF
Использование: ${0##*/} [ОПЦИИ]

Опции:
  -u, --users          вывести список пользователей и их домашних директорий
  -p, --processes      вывести список запущенных процессов (PID и команда)
  -h, --help           показать эту справку и выйти

  -l, --log PATH       перенаправить обычный вывод (stdout) в файл по пути PATH
  -e, --errors PATH    перенаправить вывод ошибок (stderr) в файл по пути PATH

Примеры:
  ${0##*/} -u
  ${0##*/} --processes --log /tmp/proc.log
  ${0##*/} -u -p -l logs/out.txt -e logs/err.txt
EOF
}

       
# Функция: проверка, что файл доступен для записи
       
check_path_writable() {
    local path="$1"   # Получаем путь
    local dir=        # Переменная для директории

    # Проверяем: если это директория — это ошибка, нужен именно файл
    if [ -d "$path" ]; then
        echo "Ошибка: '$path' — это директория, нужно указать файл" >&2
        return 1
    fi

    # Определяем директорию из пути
    dir=$(dirname -- "$path")

    # Проверяем существование директории
    if [ ! -d "$dir" ]; then
        echo "Ошибка: директория '$dir' не существует" >&2
        return 1
    fi

    # Проверяем права на запись в директорию
    if [ ! -w "$dir" ]; then
        echo "Ошибка: нет прав на запись в директорию '$dir'" >&2
        return 1
    fi

    # Пытаемся создать/очистить файл
    : > "$path" 2>/dev/null || {
        echo "Ошибка: не удалось открыть файл '$path' для записи" >&2
        return 1
    }

    return 0    # Всё хорошо
}

       
# Функция: настройка логирования
       
setup_logging() {
    # Если указан путь для логов stdout
    if [ -n "$LOG_PATH" ]; then
        check_path_writable "$LOG_PATH" || exit 1
        exec >"$LOG_PATH"     # Перенаправляем stdout в файл
    fi

    # Если указан путь для ошибок stderr
    if [ -n "$ERR_PATH" ]; then
        check_path_writable "$ERR_PATH" || exit 1
        exec 2>"$ERR_PATH"    # Перенаправляем stderr в файл
    fi
}

       
# Функция: вывод списка пользователей
       
print_users() {
    # macOS нет getent → используем /etc/passwd
    awk -F: '{printf "%-20s %s\n", $1, $6}' /etc/passwd | sort
}

       
# Функция: вывод списка процессов
       
print_processes() {
    # ps -e - список всех процессов
    # -o pid=,command= — выводим только PID и команду
    # сортировка по PID по числам
    if ps -e -o pid=,command= 2>/dev/null | sort -n; then
        :
    else
        echo "Ошибка: не удалось получить список процессов" >&2
        return 1
    fi
}

       
# Разбор аргументов (getopts)
       

# "-:" в начале и в конце optstring позволяет парсить длинные опции (--users)
while getopts ":uphl:e:-:" opt; do
    case "$opt" in
        u)
            DO_USERS=1      # Включаем вывод пользователей
            ;;
        p)
            DO_PROCESSES=1  # Включаем вывод процессов
            ;;
        h)
            print_help      # Показываем справку
            exit 0
            ;;
        l)
            LOG_PATH="$OPTARG"   # Сохраняем путь для stdout
            ;;
        e)
            ERR_PATH="$OPTARG"   # Сохраняем путь для stderr
            ;;
        -)
            # Здесь разбираем длинные опции вида --users
            case "$OPTARG" in
                users)
                    DO_USERS=1
                    ;;
                processes)
                    DO_PROCESSES=1
                    ;;
                help)
                    print_help
                    exit 0
                    ;;
                log)
                    # Берём следующий аргумент как путь
                    LOG_PATH="${!OPTIND}"
                    OPTIND=$((OPTIND + 1))
                    ;;
                errors)
                    ERR_PATH="${!OPTIND}"
                    OPTIND=$((OPTIND + 1))
                    ;;
                *)
                    echo "Неизвестная опция --$OPTARG" >&2
                    exit 1
                    ;;
            esac
            ;;
        \?)
            echo "Неизвестная опция -$OPTARG" >&2
            exit 1
            ;;
        :)
            echo "Опции -$OPTARG требуется аргумент" >&2
            exit 1
            ;;
    esac
done

# Убираем обработанные аргументы
shift $((OPTIND - 1))

# Проверяем: выбрано ли хоть одно действие?
if [ "$DO_USERS" -eq 0 ] && [ "$DO_PROCESSES" -eq 0 ]; then
    echo "Не указано действие. Используйте -u/--users или -p/--processes." >&2
    echo >&2
    print_help >&2
    exit 1
fi

# Настраиваем логи (если указаны)
setup_logging

# Выполняем действия, которые попросил пользователь
if [ "$DO_USERS" -eq 1 ]; then
    print_users
fi

if [ "$DO_PROCESSES" -eq 1 ]; then
    print_processes
fi
