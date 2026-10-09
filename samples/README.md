# Сохранённое измерение perf

`perf-report-arm64.txt` — реальный текстовый вывод опыта 5, записанный 2026-10-09 при подготовке практикума. Это запасной материал для VM, где perf недоступен, и пример чтения отчёта. **Он не является измерением компьютера студента.**

Среда: Ubuntu 26.04.1 ARM64, systemd 259, ядро 6.12.76-linuxkit (Docker Desktop), perf 7.0.14. Полная оговорка о среде — в [VALIDATION.md](../VALIDATION.md).

Команда записи:

```bash
sudo perf record -e cpu-clock:u -F 99 --call-graph fp \
  -p "$LAB_PID" -o /var/lib/lk7-lab/traces/cpu.data -- sleep 5
```

Команда отчёта:

```bash
sudo perf report --stdio --no-children --sort symbol --percent-limit 1 \
  -i /var/lib/lk7-lab/traces/cpu.data
```

Получено **488 выборок**, потерь 0; все выборки этого запуска пришлись на `mix_numbers`. Процент не обязан повториться. Сам бинарник собирался скриптом `setup.sh` из `examples/cpu-hot.c` с `-O2 -g -fno-omit-frame-pointer -fno-optimize-sibling-calls`.

`perf-stat-arm64.txt` — предшествующее пятисекундное наблюдение того же процесса. Сравните task-clock с elapsed. Значения определяются средой и конкуренцией за CPU.

Текстовые отчёты сохранены целиком; убраны только пробелы в конце строк. В них может быть предупреждение об отсутствующем `tips.txt`: на полученные выборки это не влияет. Сырые perf.data не публикуются: для их корректного разбора потребовались бы соответствующие бинарники и символы.
