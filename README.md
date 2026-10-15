# ЛК7: диагностика Linux — strace, lsof, perf

Готовый семинар **на 80 минут** для начинающих с базой Linux и сетей. Сначала соберём C-программу и исследуем ELF, затем разберём три инцидента: конфигурацию, ожидание данных и CPU. Ещё два сценария доступны как дополнительные. Все программы и команды готовы; писать код или сдавать домашнюю работу не требуется.

Теория перед семинаром: процессы, системные вызовы, файловые дескрипторы и различие между вычислением и ожиданием. В опыте 0 изучаем исходник и устройство бинарника. В последующих инцидентах начинаем с внешнего поведения программы — это наш black box debugging.

## Навигация

- [Подготовка Ubuntu до занятия](#prepare)
- [План на 80 минут](#schedule)
- [0. Сборка программы, ELF, nm, objdump и strace](#elf)
- [Расширение: статическая и динамическая линковка](#linking)
- [1. Приложение не читает конфигурацию](#config)
- [2. Процесс жив, работа не движется](#wait)
- [3. CPU занят, strace почти молчит](#cpu)
- [Дополнительно A. Порт занят, но страница открывается](#port)
- [Дополнительно B. Удалили лог, а место занято](#deleted)
- [Завершение и повтор](#reset)
- [Короткая памятка](#cheatsheet)
- [Если не получилось](#troubleshooting)
- [Что проверено](VALIDATION.md)
- [Подсказки преподавателю](INSTRUCTOR.md)

## Как выполнять команды

- Все команды ниже выполняются **внутри Ubuntu VM**, через SSH или консоль VirtualBox. `127.0.0.1` здесь относится к Ubuntu.
- Подойдёт обычный пользователь с `sudo` или root. Примеры приложений работают под отдельным пользователем `lk7-demo`.
- Копируйте блоки по порядку. Ошибки, помеченные как ожидаемые, — часть опыта. Не запускайте README целиком через `set -e`.
- `LAB_PID` — переменная текущего терминала; после нового входа присвойте её заново командой из соответствующего опыта.
- Для опыта 2 удобно открыть две SSH-сессии. В нём `Ctrl+C` завершает **подключённый strace**, а служба продолжает работать.
- В примерах только тестовые данные. Реальная трассировка может записать содержимое запросов, токены и другие чувствительные данные.

<a id="prepare"></a>
## Подготовка Ubuntu до занятия

### 1. Виртуальная машина

Подходит VM с прошлого семинара: **Ubuntu Server 26.04.1**, systemd, 2 CPU и 4 GB RAM. Примеры собираются локально и подходят ARM64 на Apple Silicon и AMD64 на Windows/Intel Mac. Держите около 1 GB свободного места для пакетов и небольших trace-файлов.

Если VM ещё нет, воспользуйтесь [инструкцией прошлого практикума по VirtualBox и SSH](https://github.com/vmeshche/sre-systemd-lab#vm). Для Mac M1–M4 нужен ARM64 ISO, для обычного Windows x86-64 — AMD64. Для учебного HTTP-порта 8091 проброс на хост не требуется: используем `curl` внутри Ubuntu.

### 2. Пакеты и примеры

```bash
sudo apt update
sudo apt install -y git build-essential binutils file strace lsof python3 curl procps psmisc iproute2 time
cd ~
git clone https://github.com/vmeshche/sre-linux-troubleshooting-lab.git
cd ~/sre-linux-troubleshooting-lab
sudo bash scripts/setup.sh
sudo bash scripts/reset.sh
bash scripts/check-environment.sh
```

Если репозиторий уже скачан, вместо повторного `git clone` выполните в нём `git pull --ff-only`.

`setup.sh` создаёт пользователя `lk7-demo`, собирает четыре маленькие C-программы с символами отладки, устанавливает службы `lk7-*` и тестовые данные. Службы не включаются в автозагрузку. `reset.sh` останавливает только эти службы и возвращает исходные неисправности. Он не меняет учебные службы `course-web` и `lk3-*`.

Ожидаем `Ready for ELF and service cases`. Проверка `perf` выполняется отдельно ниже. При сообщении о занятом порте 8091 сначала определите его владельца: `sudo ss -ltnp 'sport = :8091'`.

### 3. Проверить perf заранее

На **Ubuntu 26.04** `perf` устанавливается отдельным пакетом:

```bash
sudo apt install -y linux-perf
perf --version
sudo perf stat -e task-clock,context-switches,page-faults -- sleep 1
```

Ожидаем таблицу счётчиков. `task-clock` у спящего процесса очень мал — это CPU-время, а не длительность сна.

На более старых Ubuntu пакет может называться иначе: `linux-tools-common` и `linux-tools-$(uname -r)`. Не переносите эту старую инструкцию на 26.04 автоматически. Если `apt` не находит пакет, проверьте `/etc/os-release` и `apt-cache policy linux-perf`.

В VM аппаратные события `cycles` и `instructions` могут быть недоступны. В основном опыте используем **программное событие `cpu-clock`**. Если недоступно и оно, в опыте 3 есть запасной маршрут с сохранённым примером. Не нужно отключать защиту всей системы или менять глобальный `perf_event_paranoid` ради занятия.

До занятия удобно выключить VM и сохранить в VirtualBox снимок `lk7-ready`. После восстановления снимка при необходимости обновите репозиторий.

### Что лежит в репозитории

| Каталог | Назначение |
|---|---|
| `examples/` | Исходники приложений для диагностики |
| `examples/elf/` | Два исходника C и заголовок для ручной сборки, ELF и линковки |
| `units/` | Шесть готовых systemd-служб |
| `scripts/` | Подготовка, проверка окружения и сброс |
| `samples/` | Запись профиля для разбора при недоступном perf |

<a id="schedule"></a>
## План на 80 минут

| Время | Действие |
|---|---|
| 0–5 | Проверка подготовленного стенда |
| 5–25 | Опыт 0: компиляция, секции, символы, objdump, strace, strip |
| 25–40 | Опыт 1: конфигурация, ENOENT и EACCES |
| 40–55 | Опыт 2: ожидание данных, strace и lsof |
| 55–70 | Опыт 3: CPU, границы strace и perf |
| 70–80 | Объяснение результатов, вопросы и сброс |

Расширение про линковку и дополнительные случаи с портом и удалённым логом выполняйте при наличии времени или используйте вместо одного из основных инцидентов. Они полностью описаны и не требуют сдачи результатов.

**На каждую неисправность используем один порядок:** симптом → гипотеза → короткое наблюдение → изменение → повторная проверка полезного результата.

<a id="elf"></a>
## 0. Исходник, ELF, символы и системные вызовы

В этом опыте исходник открыт: сначала строим модель программы, затем используем её в расследованиях. Все команды выполняйте из корня репозитория **в Ubuntu**, без `sudo`. `nm`, `objdump`, `readelf`, `ar` и `strip` входят в пакет `binutils`.

### 0.1. Прочитать и скомпилировать два исходника

```bash
cd ~/sre-linux-troubleshooting-lab
cat examples/elf/main.c
cat examples/elf/calculate.h
cat examples/elf/calculate.c
mkdir -p build/elf-lab

gcc -O0 -g -fno-inline -Wall -Wextra -c examples/elf/main.c \
  -o build/elf-lab/main.o
gcc -O0 -g -fno-inline -Wall -Wextra -c examples/elf/calculate.c \
  -o build/elf-lab/calculate.o
file build/elf-lab/main.o
```

`main` передаёт `7` в функцию `calculate`, та умножает число на `6`. Затем программа выводит строку и результат. `-c` создаёт объектный файл без финальной линковки; `-O0` упрощает соответствие исходника и инструкций; `-g` добавляет отладочные сведения.

В `file` ожидаем **ELF … relocatable … with debug_info, not stripped**. На Apple Silicon архитектура будет AArch64, на обычном Windows/Intel Mac — x86-64. Это зависит от Ubuntu VM, где идёт сборка. Если видите Mach-O, команда выполнена в macOS — перейдите в VM.

### 0.2. Найти секции и символы объектного файла

```bash
readelf -SW build/elf-lab/main.o
objdump -h build/elf-lab/main.o
nm build/elf-lab/main.o
nm build/elf-lab/calculate.o
```

В длинном выводе найдите только эти строки:

| Что ищем | Где ожидаем увидеть | Что это означает |
|---|---|---|
| `main`, `calculate` | `.text`, буква `T` в `nm` у определения | Машинный код функций |
| `initialized` | `.data`, `D` | Глобальная переменная с начальным значением 7 |
| `zero_initialized` | `.bss`, `B` | Глобальная переменная с начальным нулевым значением |
| `greeting` | `.rodata`, `R` | Массив с неизменяемой строкой |
| `calculate`, `printf` в `main.o` | `U` | Ссылки на определения, которых нет в этом объектном файле |

В `readelf` у `.bss` тип **NOBITS**: размер для нулевых данных описан, но сами байты нулей не занимают соответствующий объём в файле. Буквы `nm` описывают символы, а не состояние процесса. Адрес/значение символа в `.o` может быть смещением внутри секции — это ещё не окончательный адрес в работающей программе.

**Контрольный вопрос:** почему `calculate` есть в обоих выводах, но с разными буквами? В `main.o` функция используется (`U`), а `calculate.o` содержит её определение (`T`).

### 0.3. Связать части и посмотреть инструкции

```bash
gcc build/elf-lab/main.o build/elf-lab/calculate.o -o build/elf-lab/demo
./build/elf-lab/demo
file build/elf-lab/demo
nm build/elf-lab/demo | grep -E ' (main|calculate|initialized|zero_initialized|greeting)$'
objdump -d --disassemble=calculate build/elf-lab/demo
objdump -S --disassemble=calculate build/elf-lab/demo
```

Программа печатает **`hello from ELF: 42`**. В `nm` обе функции имеют определения. `objdump -d` показывает инструкции функции, `-S` добавляет доступные строки исходника благодаря отладочной информации. Полезно найти имя `calculate`, адреса и возврат из функции. Учить все инструкции не нужно.

Числа адресов, инструкции и служебные секции зависят от архитектуры и компилятора. На ARM64 и AMD64 листинги будут разными. Адрес из ELF также не обязан совпадать с runtime-адресом при PIE/ASLR. Динамический `printf` может оставаться внешним символом и в исполняемом файле: его предоставляет libc.

### 0.4. Посмотреть выполнение через strace

```bash
strace -o build/elf-lab/demo.trace -e trace=write,exit_group ./build/elf-lab/demo
cat build/elf-lab/demo.trace
```

Среди строк ожидаем:

```text
write(1, "hello from ELF: 42\n", 19) = 19
exit_group(0) = ?
+++ exited with 0 +++
```

Строка содержит **19 байт**, включая перевод строки. Результат `write` показывает, сколько байт записано. Имена `main` и `calculate` в trace не появятся: это обычные функции приложения. `printf` — библиотечная функция, которая форматирует и буферизует вывод; в данном запуске она приводит к `write`. В общем случае один `printf` не обязан соответствовать одному `write`.

**Вывод:** `objdump` показывает код в файле, `strace` — обращения к ядру при запуске. По отсутствию функции в trace нельзя заключить, что она не выполнялась.

### 0.5. Убрать символы из копии

```bash
cp build/elf-lab/demo build/elf-lab/demo-stripped
strip --strip-all build/elf-lab/demo-stripped
./build/elf-lab/demo-stripped
nm build/elf-lab/demo-stripped
strace -o build/elf-lab/stripped.trace -e trace=write,exit_group \
  ./build/elf-lab/demo-stripped
cat build/elf-lab/stripped.trace
nm -D build/elf-lab/demo-stripped
```

Вывод программы остаётся **`hello from ELF: 42`**. Обычный `nm` сообщает **no symbols**; это ожидаемо. `strace` продолжает показывать `write`: символы приложения для распознавания syscall не нужны. `nm -D` показывает оставшиеся динамические символы, необходимые для работы с библиотеками.

Мы удалили таблицу обычных символов и отладочные сведения из копии. `strip --strip-debug` удаляет только отладочную информацию и дал бы другой результат. Код остаётся доступен для дизассемблирования через `objdump -d`, но искать его по имени `calculate` уже нельзя. Профилировщику без отдельного файла символов будет сложнее подписать этот участок кода.

**Основной маршрут:** после опыта 0 переходите к [инциденту 1](#config). Следующий блок — необязательное расширение.

<a id="linking"></a>
## Расширение: статическая и динамическая линковка

Этот блок удобно показать в конце лекции или выполнить при наличии ещё **10–15 минут**. Он продолжает опыт 0; сначала выполните 0.1–0.3. Создадим свою маленькую библиотеку, чтобы не зависеть от наличия статической libc.

### Два способа подключить calculate

```bash
mkdir -p build/elf-lab/lib
ar rcs build/elf-lab/lib/libcalculate.a build/elf-lab/calculate.o
gcc build/elf-lab/main.o build/elf-lab/lib/libcalculate.a \
  -o build/elf-lab/demo-archive

gcc -O0 -g -fPIC -Wall -Wextra -c examples/elf/calculate.c \
  -o build/elf-lab/calculate.pic.o
gcc -shared -Wl,-soname,libcalculate.so \
  -o build/elf-lab/lib/libcalculate.so build/elf-lab/calculate.pic.o
gcc build/elf-lab/main.o -Lbuild/elf-lab/lib -lcalculate \
  '-Wl,-rpath,$ORIGIN/lib' -o build/elf-lab/demo-shared

./build/elf-lab/demo-archive
./build/elf-lab/demo-shared
readelf -d build/elf-lab/demo-archive | grep NEEDED
readelf -d build/elf-lab/demo-shared | grep -E 'NEEDED|RUNPATH'
```

Оба запуска печатают **`hello from ELF: 42`**.

- В `demo-archive` нужный объект из архива `.a` включён линкером в исполняемый файл. В `NEEDED` нет `libcalculate.so`.
- У `demo-shared` в `NEEDED` есть **libcalculate.so** и **libc.so.6**. Динамический загрузчик найдёт и отобразит эти библиотеки при запуске.
- `$ORIGIN/lib` означает каталог `lib` рядом с исполняемым файлом. Одинарные кавычки в команде важны: `$ORIGIN` должен получить загрузчик, а не раскрыть shell. В обычной сборке Ubuntu это записывается как `RUNPATH`.
- **demo-archive не полностью статический:** наша функция включена из `.a`, но libc по-прежнему динамическая. Статическая линковка отдельной библиотеки и полностью статический бинарник — разные вещи.

### Библиотека потерялась при переносе программы

```bash
mkdir -p build/elf-lab/isolated
cp build/elf-lab/demo-shared build/elf-lab/isolated/demo-shared
./build/elf-lab/isolated/demo-shared
strace -o build/elf-lab/missing-library.trace -e trace=%file \
  ./build/elf-lab/isolated/demo-shared
grep libcalculate build/elf-lab/missing-library.trace
```

Ожидаем ошибку загрузчика **libcalculate.so: cannot open shared object file** и неуспешный запуск, обычно код 127. Скопировали бинарник, но рядом с ним нет `lib/libcalculate.so`; `main` ещё не начал выполняться. В trace видно, где загрузчик ищет библиотеку, и ответы `ENOENT`. Количество путей и syscall зависит от версии libc и окружения.

Укажем путь только для одного запуска:

```bash
LD_LIBRARY_PATH="$PWD/build/elf-lab/lib" ./build/elf-lab/isolated/demo-shared
strace -o build/elf-lab/shared.trace -e trace=%file,mmap ./build/elf-lab/demo-shared
grep libcalculate build/elf-lab/shared.trace
```

Снова ожидаем **`hello from ELF: 42`**. Это учебный способ проверить гипотезу. Для поставки приложения нужно обеспечить правильную установку библиотек и пути их поиска. Глобально менять `LD_LIBRARY_PATH` не требуется.

**Вывод:** служебные `openat` и `mmap` в начале trace могут принадлежать динамическому загрузчику. Отсутствующая библиотека способна остановить программу ещё до `main`.


<a id="config"></a>
## 1. Приложение не читает конфигурацию

### Увидеть симптом

```bash
sudo systemctl start lk7-config.service
systemctl status lk7-config.service --no-pager
sudo journalctl -b -u lk7-config.service --no-pager -n 15
```

Ожидаем неуспешный запуск и `startup failed: No such file or directory`. У приложения нет подробного сообщения с нужным путём. Посмотрим, какой файл оно открывает.

### Запустить программу под трассировкой

```bash
sudo -u lk7-demo strace -f -s 128 -o /var/lib/lk7-lab/traces/config.trace \
  -e trace=%file /opt/lk7-lab/bin/config
sudo cat /var/lib/lk7-lab/traces/config.trace
```

Программа снова завершится с ошибкой, а trace останется в файле. Ключевая строка выглядит примерно так:

```text
openat(AT_FDCWD, "/etc/lk7-lab/app.conf", O_RDONLY) = -1 ENOENT (No such file or directory)
```

- `openat` — попытка открыть файл.
- Путь — тот, который **фактически запросило приложение**.
- `O_RDONLY` — открыть для чтения.
- `-1 ENOENT` — вызов не выполнился: отсутствует файл или один из компонентов пути.

В начале trace могут быть другие `ENOENT`: загрузчик библиотек проверяет несколько путей. Одна ошибка не доказывает причину сбоя; здесь путь конфигурации совпадает с моментом завершения приложения.

```bash
ls -l /etc/lk7-lab/
```

Есть `service.conf`, но приложение ищет `app.conf`.

### Восстановить и проверить

```bash
sudo install -m 0644 /etc/lk7-lab/service.conf /etc/lk7-lab/app.conf
sudo systemctl start lk7-config.service
systemctl show lk7-config.service -p Result -p ExecMainStatus
sudo journalctl -b -u lk7-config.service --no-pager -n 10
```

Ожидаем `Result=success`, `ExecMainStatus=0` и сообщение `config loaded: message=ready`. Служба `Type=oneshot` после успеха возвращается в `inactive` — это нормально.

### Увидеть другую причину с похожим симптомом

Теперь файл существует, но доступен только root:

```bash
sudo chmod 0600 /etc/lk7-lab/app.conf
sudo -u lk7-demo strace -o /var/lib/lk7-lab/traces/denied.trace \
  -e trace=%file /opt/lk7-lab/bin/config
sudo tail -n 8 /var/lib/lk7-lab/traces/denied.trace
```

Ожидаем `EACCES (Permission denied)`. Важно запускать приложение как `lk7-demo`, как в его unit-файле: root может прочитать файл и скрыть неисправность прав.

```bash
sudo chmod 0644 /etc/lk7-lab/app.conf
sudo systemctl start lk7-config.service
systemctl show lk7-config.service -p Result -p ExecMainStatus
```

**Вывод:** похожий пользовательский симптом может означать разные ошибки ОС. Исправление следует из конкретного пути, режима доступа и errno.

<a id="wait"></a>
## 2. Процесс жив, работа не движется

### Посмотреть состояние

```bash
sudo systemctl start lk7-wait.service
LAB_PID=$(systemctl show lk7-wait.service -p MainPID --value)
ps -p "$LAB_PID" -o pid,stat,pcpu,wchan:24,args
sudo lsof -nP -a -p "$LAB_PID" -d 3
sudo journalctl -b -u lk7-wait.service --no-pager -n 8
```

Ожидаем живой процесс с небольшим CPU, обычно состоянием `S` и ожиданием, связанным с pipe. В FD 3 — FIFO `/var/lib/lk7-lab/work/inbox`. Колонка `WCHAN` зависит от ядра и прав: возможны `pipe_read`, `0` или другое имя. Это подсказка, не самостоятельный диагноз.

FIFO — именованный канал. Наш worker читает из него и ждёт, пока кто-нибудь пришлёт данные.

### Терминал A: подключить strace

```bash
LAB_PID=$(systemctl show lk7-wait.service -p MainPID --value)
sudo strace -tt -T -yy -s 64 -e trace=read,write -p "$LAB_PID"
```

Строка `read(...)` может долго оставаться незавершённой. Не закрывайте трассировку: ожидание — наблюдаемый результат.

### Терминал B: передать данные

Откройте вторую SSH-сессию той же Ubuntu:

```bash
printf 'continue\n' | sudo tee /var/lib/lk7-lab/work/inbox
```

В терминале A вызов `read` завершится и будет виден текст `continue\n`, затем `write` в журнал. Суффикс `<...>` от `-T` покажет длительность наблюдаемого вызова; конкретное число зависит от того, как долго вы ждали. Worker снова перейдёт к следующему `read`.

В терминале A нажмите **Ctrl+C**, затем:

```bash
systemctl is-active lk7-wait.service
sudo journalctl -b -u lk7-wait.service --no-pager -n 10
sudo systemctl stop lk7-wait.service
```

До остановки ожидаем `active` и `received: continue` в журнале. `Ctrl+C` остановил прикреплённый трассировщик; сам процесс продолжал работать.

**Вывод:** долгий `read` может означать нормальное ожидание данных. `-T` включает ожидание, а не измеряет только работу CPU внутри ядра. В этом опыте причина отсутствия результата — отсутствие входного сообщения.

<a id="cpu"></a>
## 3. CPU занят, strace почти молчит

### Подтвердить симптом

```bash
sudo systemctl start lk7-cpu.service
LAB_PID=$(systemctl show lk7-cpu.service -p MainPID --value)
sleep 2
ps -p "$LAB_PID" -o pid,stat,pcpu,time,args
```

Ожидаем высокую загрузку примерно одного логического CPU. `%CPU` в `ps` — среднее за время жизни процесса, а не мгновенное измерение.

Посмотрим системные вызовы в течение трёх секунд:

```bash
sudo timeout --signal=INT --kill-after=2s 3s strace -c -p "$LAB_PID"
systemctl is-active lk7-cpu.service
```

`timeout` обычно вернёт **124** — запланированное окончание наблюдения. Системных вызовов будет мало или не будет совсем. Служба остаётся `active`: программа вычисляет в userspace, и strace не показывает инструкции внутри функций. `clock_gettime` здесь может обслуживаться через vDSO без syscall.

### Если perf доступен: счётчики и профиль

```bash
sudo perf stat -e task-clock,context-switches,page-faults -p "$LAB_PID" -- sleep 5
```

Сравните CPU-время `task-clock` с пятью секундами наблюдения. При свободном CPU оно будет близко к пяти секундам; квота или конкуренция могут уменьшить его. Счётчики ещё не называют горячую функцию.

```bash
sudo perf record -e cpu-clock:u -F 99 --call-graph fp \
  -p "$LAB_PID" -o /var/lib/lk7-lab/traces/cpu.data -- sleep 5
sudo perf report --stdio --no-children --sort symbol --percent-limit 1 \
  -i /var/lib/lk7-lab/traces/cpu.data
```

Ожидаем среди лидеров функцию **mix_numbers**. Точный процент зависит от измерения. Программа собрана с символами отладки и frame pointers; это помогает увидеть имена и цепочки вызовов.

- `cpu-clock:u` — программные выборки CPU-времени в userspace.
- `-F 99` — запрошенная частота выборок, около 99 в секунду; фактическая может отличаться.
- `--call-graph fp` — записать цепочки вызовов с помощью frame pointers.
- `--no-children` — сравнивать собственные выборки функций без включения времени их потомков.

**Процент в perf report — доля веса записанных выборок выбранного события**, а не процент времени ответа запроса. CPU-профиль не объясняет сам по себе долгий сон или ожидание сети.

### Если perf недоступен в этой VM

Сохраните сообщение ошибки и прочитайте реальный пример, записанный при подготовке практикума:

```bash
cd ~/sre-linux-troubleshooting-lab
cat samples/perf-report-arm64.txt
```

Это **сохранённое измерение другого запуска**, а не результат вашей VM. Найдите `mix_numbers` и сопоставьте его с предыдущим наблюдением: CPU занят, а системных вызовов почти нет. При желании после разбора откройте `examples/cpu-hot.c` и найдите вычислительный цикл.

Если видите `Operation not permitted`, проверьте запуск через `sudo` и настройки окружения. Если событие не поддерживается или образ VM не предоставляет нужные возможности, используйте сохранённый пример. Менять глобальные настройки защиты для занятия не требуется.

### Остановить нагрузку

```bash
sudo systemctl stop lk7-cpu.service
```

Все длительные примеры дополнительно ограничены 15 минутами. После автоматического завершения снова запустите нужную службу и заново получите `LAB_PID`.

<a id="port"></a>
## Дополнительно A. Порт занят, но страница открывается

### Воспроизвести инцидент

```bash
sudo systemctl start lk7-port-owner.service
curl --fail --retry 5 --retry-delay 1 --retry-connrefused --max-time 3 http://127.0.0.1:8091/
sudo systemctl start lk7-web.service
sleep 1
systemctl status lk7-web.service --no-pager
sudo journalctl -b -u lk7-web.service --no-pager -n 12
```

`curl` возвращает **old application**, а нужный `lk7-web` завершается с `Address already in use`. Команда `systemctl start` для `Type=exec` иногда успевает вернуть успех до последующей ошибки приложения; проверяем журнал и реальный ответ.

### Найти владельца слушающего сокета

```bash
sudo ss -ltnp 'sport = :8091'
sudo lsof -nP -iTCP:8091 -sTCP:LISTEN
```

В выводе найдите `PID`, пользователя и адрес `127.0.0.1:8091`. `-nP` отключает преобразование адресов в DNS-имена и портов в имена служб. В колонке FD, например `3u`, число — дескриптор, а `u` означает чтение и запись.

Получим найденный PID и сопоставим его с unit:

```bash
LAB_LISTENER_PID=$(sudo lsof -t -nP -iTCP:8091 -sTCP:LISTEN | head -n 1)
ps -p "$LAB_LISTENER_PID" -o pid,ppid,user,stat,args
systemctl status "$LAB_LISTENER_PID" --no-pager
```

Ожидаем связь с **lk7-port-owner.service**, а не с `lk7-web.service`. Здесь соединение и HTTP работают, но запрос попадает в другой процесс.

### Восстановить полезный результат

```bash
sudo systemctl stop lk7-port-owner.service
sudo systemctl reset-failed lk7-web.service
sudo systemctl start lk7-web.service
curl --fail --retry 5 --retry-delay 1 --retry-connrefused --max-time 3 http://127.0.0.1:8091/
sudo lsof -nP -iTCP:8091 -sTCP:LISTEN
```

Ожидаем **new application**. PID слушателя принадлежит новому экземпляру. После наблюдений:

```bash
sudo systemctl stop lk7-web.service
```

**Вывод:** открытый порт и успешный HTTP-ответ ещё не подтверждают, что запрос обслуживает нужный процесс.

<a id="deleted"></a>
## Дополнительно B. Удалили лог, а место занято

### Создать небольшой файл и открыть его процессом

```bash
sudo systemctl start lk7-deleted.service
sleep 1
LAB_PID=$(systemctl show lk7-deleted.service -p MainPID --value)
sudo journalctl -b -u lk7-deleted.service --no-pager -n 8
sudo ls -lh /var/lib/lk7-lab/log/demo.log
sudo du -h /var/lib/lk7-lab/log
```

Ожидаем `16 MiB written` в журнале и файл примерно 16 MiB. Если запись ещё не завершена, повторите просмотр журнала. Программа намеренно держит дескриптор открытым и больше не увеличивает файл.

### Удалить имя и найти оставшийся открытый объект

```bash
sudo rm /var/lib/lk7-lab/log/demo.log
sudo du -h /var/lib/lk7-lab/log
sudo lsof -nP -a -p "$LAB_PID" +L1
```

Путь исчез, размер каталога уменьшился. Но `lsof` показывает файл размером `16777216`, нулевым числом ссылок и пометкой `(deleted)`.

Для нашего маленького приложения лог находится в FD 3; проверьте колонку FD в `lsof`:

```bash
sudo readlink "/proc/$LAB_PID/fd/3"
sudo stat -Lc 'size=%s bytes; blocks=%b blocks of 512 bytes; links=%h' "/proc/$LAB_PID/fd/3"
```

`stat` следует по дескриптору и показывает существующий открытый объект. Число блоков зависит от файловой системы. Это один из случаев, когда `du` и `df` показывают разные вещи: `du` обходит имена, а `df` сообщает занятость файловой системы. Изменение общего `df` на 16 MiB может быть незаметно на фоне другой активности; основное доказательство — открытый FD и нулевой link count.

### Попросить приложение переоткрыть лог

Наш учебный процесс **специально реализует** переоткрытие по `SIGUSR1`:

```bash
sudo systemctl kill --kill-whom=main --signal=SIGUSR1 lk7-deleted.service
sleep 1
sudo journalctl -b -u lk7-deleted.service --no-pager -n 8
sudo ls -lh /var/lib/lk7-lab/log/demo.log
sudo lsof -nP -a -p "$LAB_PID" +L1
```

Ожидаем новый маленький лог и отсутствие удалённого файла в `lsof`. Пустой результат последней команды здесь нормален; код возврата при отсутствии совпадений может зависеть от версии lsof. Старый файл освобождается после закрытия последнего открытого дескриптора; снимки и особенности файловой системы могут влиять на фактически освободившееся место.

Сигнал переоткрытия зависит от конкретного приложения. Не отправляйте `SIGUSR1` произвольному процессу: действие по умолчанию может завершить его.

```bash
sudo systemctl stop lk7-deleted.service
```

**Вывод:** удалить имя файла и закрыть открытый файл — разные действия.

<a id="reset"></a>
## Завершение и повтор

Завершите прикреплённые `strace` через `Ctrl+C`. Затем:

```bash
cd ~/sre-linux-troubleshooting-lab
sudo bash scripts/reset.sh
bash scripts/check-environment.sh
```

Ожидаем остановленные службы, свободный порт 8091 и отсутствие `app.conf`. Конфигурационная неисправность готова к повтору; остальные случаи создаются своими командами запуска. История journal, сохранённые trace-файлы и сборки в `build/elf-lab` остаются для разбора. `reset.sh` не удаляет результаты ручной компиляции; повторные команды сборки перезаписывают их. Старые записи в журнале отличайте по времени.

После изучения можно удалить только файлы наблюдений этого практикума:

```bash
sudo rm -f /var/lib/lk7-lab/traces/config.trace /var/lib/lk7-lab/traces/denied.trace \
  /var/lib/lk7-lab/traces/cpu.data /var/lib/lk7-lab/traces/cpu.data.old
```

Для полного возврата к началу восстановите снимок `lk7-ready`.

<a id="cheatsheet"></a>
## Короткая памятка

| Вопрос | Команда / наблюдение |
|---|---|
| Какие секции в объектном файле? | `readelf -SW build/elf-lab/main.o` |
| Где определена функция? | `nm build/elf-lab/calculate.o` |
| Какие инструкции у функции? | `objdump -d --disassemble=calculate build/elf-lab/demo` |
| Какие библиотеки нужны при запуске? | `readelf -d build/elf-lab/demo-shared` |
| Какой процесс работает и в каком состоянии? | `ps -p "$LAB_PID" -o pid,ppid,user,stat,pcpu,wchan:24,args` |
| Что приложение просит у ядра? | `strace -f -s 128 -o trace.txt ./program` |
| Какой файл не открывается? | `strace -e trace=%file ./program` |
| Что происходит у работающего процесса? | `sudo strace -tt -T -yy -p "$LAB_PID"` |
| Сколько вызовов и ошибок? | `strace -c ./program`; время по умолчанию — оценка CPU-времени в ядре |
| Какие файлы открыл процесс? | `sudo lsof -nP -p "$LAB_PID"` |
| Кто слушает TCP-порт? | `sudo lsof -nP -iTCP:8091 -sTCP:LISTEN` |
| Есть открытые файлы без имени? | `sudo lsof -nP -a -p "$LAB_PID" +L1` |
| Где расходуется CPU? | Короткий `perf record` и `perf report`; начать с программных событий |

При запуске под strace `-f` следует за **новыми** дочерними процессами и потоками. При `-f -p PID` strace подключается и к существующим потокам этого процесса; уже существующие отдельные дочерние процессы не добавляются автоматически. Их PID нужно выбрать отдельно.

Фильтр `-e` уменьшает вывод, но в обычном режиме ptrace не гарантирует меньше остановок. `--seccomp-bpf` может отфильтровать остановки для запускаемого процесса с `-f`, но имеет ограничения и не является универсальным ускорением attach.

<a id="troubleshooting"></a>
## Если не получилось

| Симптом | Что проверить |
|---|---|
| `objdump` / `nm` / `readelf`: command not found | Установите `binutils` в Ubuntu VM |
| В `file` указан Mach-O | Сборка запущена на macOS. Выполните команды в Ubuntu VM |
| `nm`: no symbols после strip | Ожидаемо. Для исходного бинарника используйте `build/elf-lab/demo` |
| `objdump -S` не показывает строки C | Нужны сборка с `-g` и исходники по сохранённому пути |
| `strace: attach: ptrace(...): Operation not permitted` | Пользователь процесса, `sudo`, Yama/LSM, контейнерные ограничения и наличие другого трассировщика. Для первого опыта используйте запуск программы под strace, как в инструкции |
| Trace не показывает ожидаемый дочерний процесс | Для запуска используйте `-f`; для уже работающего отдельного ребёнка выберите его PID |
| `strace -p` ничего не печатает | Приложение может вычислять в userspace или уже ждать в syscall. Посмотрите CPU, состояние и открытые FD |
| В опыте 1 не получается EACCES | Приложение должно запускаться через `sudo -u lk7-demo`, а файл принадлежать root с режимом 0600 |
| `lsof` пустой или неполный | Процесс успел завершиться, нужен `sudo`, либо вы смотрите из другого namespace |
| `lsof +L1` пуст после исправления | Это ожидается: открытых удалённых файлов больше нет; отсутствие совпадений ожидаемо |
| `perf: command not found` на 26.04 | Установите `linux-perf`, затем выполните предварительную проверку |
| `perf` запрещён или событие не поддерживается | Попробуйте указанное программное событие с `sudo`; затем используйте сохранённый профиль |
| В perf только адреса или `[unknown]` | Нужны доступный ELF с символами и корректный метод разворачивания стека; снова выполните setup.sh на остановленном стенде |
| PID стал 0 / изменился | Служба завершилась; проверьте journal, перезапустите её и заново присвойте `LAB_PID` |
| VM стала медленнее | Остановите `lk7-cpu.service` и трассировщики, затем повторите короткое наблюдение |

## Первоисточники

- [strace](https://man7.org/linux/man-pages/man1/strace.1.html), [ptrace](https://man7.org/linux/man-pages/man2/ptrace.2.html), [Yama](https://docs.kernel.org/admin-guide/LSM/Yama.html).
- [lsof](https://man7.org/linux/man-pages/man8/lsof.8.html), [proc_pid_wchan](https://man7.org/linux/man-pages/man5/proc_pid_wchan.5.html).
- [perf stat](https://man7.org/linux/man-pages/man1/perf-stat.1.html), [perf record](https://man7.org/linux/man-pages/man1/perf-record.1.html), [perf report](https://man7.org/linux/man-pages/man1/perf-report.1.html), [ограничения безопасности perf](https://docs.kernel.org/admin-guide/perf-security.html).

- [ELF: формат, секции и символы](https://man7.org/linux/man-pages/man5/elf.5.html)
- [GNU objdump](https://sourceware.org/binutils/docs/binutils/objdump.html), [nm](https://sourceware.org/binutils/docs/binutils/nm.html), [readelf](https://sourceware.org/binutils/docs/binutils/readelf.html), [strip](https://sourceware.org/binutils/docs/binutils/strip.html)
- [Динамический загрузчик ld.so](https://man7.org/linux/man-pages/man8/ld.so.8.html)
