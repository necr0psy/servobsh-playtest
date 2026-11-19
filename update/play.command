#!/bin/bash
# One entry point: reuse/start this server, wait for readiness, launch Prism + Quick Play.
set -euo pipefail
cd "$(dirname "$0")"
server_dir=$PWD
fail() { echo "$*" >&2; if [[ -t 0 ]]; then read -r -p 'Нажми Enter, чтобы закрыть окно.' _; fi; exit 1; }
[[ -f server.jar && -f client-profile/mmc-pack.json ]] || fail 'Распакуй архив целиком: не найдены файлы сервера/клиента.'
prism=${EVENT_PRISM:-/Applications/Prism Launcher.app/Contents/MacOS/prismlauncher}
[[ -x "$prism" ]] || prism="$HOME/Applications/Prism Launcher.app/Contents/MacOS/prismlauncher"
if [[ ! -x "$prism" ]]; then
  echo 'Запускаю сервер. Открой Minecraft Java 1.21.11 и зайди на localhost:25565.'
  exec bash "$server_dir/start.command"
fi
prism_data=${EVENT_PRISM_DATA:-$HOME/Library/Application Support/PrismLauncher}
player=${EVENT_PLAYER:-$(cat player-name.txt)}
[[ "$player" =~ ^[A-Za-z0-9_]{3,16}$ ]] || fail 'В player-name.txt нужен ник Minecraft (3–16 латинских букв, цифр или _).'
instance=servobsh-local
target="$prism_data/instances/$instance"
if [[ ! -f "$target/instance.cfg" ]]; then
  mkdir -p "$prism_data/instances"
  staging=$(mktemp -d "$prism_data/instances/.servobsh-XXXXXX")
  cp -R client-profile/. "$staging/"
  mv "$staging" "$target"
fi
port=$(awk -F= '$1=="server-port" {gsub(/\r/,"",$2);print $2}' server.properties)
port=${port:-25565}
[[ "$port" =~ ^[0-9]+$ ]] || fail 'Неверный server-port в server.properties.'
mkdir -p .local-session
if ! mkdir .local-session/launch.lock 2>/dev/null; then
  prior=$(cat .local-session/launch.lock/pid 2>/dev/null || true)
  if [[ -z "$prior" ]]; then sleep 1; prior=$(cat .local-session/launch.lock/pid 2>/dev/null || true); fi
  if [[ "$prior" =~ ^[0-9]+$ ]] && kill -0 "$prior" 2>/dev/null; then
    echo 'Запуск уже идёт — дождись открытия Minecraft.'; exit 0
  fi
  rm -f .local-session/launch.lock/pid
  rmdir .local-session/launch.lock 2>/dev/null || fail 'Не удалось убрать старую блокировку запуска.'
  mkdir .local-session/launch.lock
fi
echo $$ > .local-session/launch.lock/pid
trap 'rm -f .local-session/launch.lock/pid; rmdir .local-session/launch.lock 2>/dev/null || true' EXIT
server_pid=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | head -1 || true)
if [[ -n "$server_pid" ]]; then
  running_dir=$(lsof -a -p "$server_pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
  [[ "$running_dir" == "$server_dir" ]] || fail "Порт $port занят сервером из другой папки. Останови ту копию и повтори запуск."
  echo 'Твой сервер уже работает. Подключаю Minecraft...'
else
  if ! grep -q '^eula=true' eula.txt 2>/dev/null; then
    echo 'Перед первым запуском прочитай Minecraft EULA: https://aka.ms/MinecraftEULA'
    read -r -p 'Если принимаешь условия, введи yes: ' answer
    [[ "$answer" == yes ]] || exit 1
    printf 'eula=true\n' > eula.txt
  fi
  echo 'Запускаю сервер. Первый запуск с загрузкой файлов может занять несколько минут...'
  nohup bash "$server_dir/start.command" > .local-session/server.log 2>&1 < /dev/null &
  server_pid=$!
  echo "$server_pid" > .local-session/server.pid
fi
ready=false
for ((i=0; i<600; i++)); do
  kill -0 "$server_pid" 2>/dev/null || fail 'Сервер завершился. Подробности: .local-session/server.log и logs/latest.log.'
  if nc -z -G 1 127.0.0.1 "$port" 2>/dev/null && grep -q 'Done (.*)!' logs/latest.log 2>/dev/null; then ready=true; break; fi
  sleep 1
done
[[ "$ready" == true ]] || fail 'За 10 минут сервер не загрузился. Смотри .local-session/server.log.'
echo "Сервер готов. Открываю Minecraft под $player → localhost:$port"
prism_app=${prism%/Contents/MacOS/*}
/usr/bin/open -n -a "$prism_app" --args --dir "$prism_data" --launch "$instance" --profile "$player" --server "127.0.0.1:$port"
echo 'Первый вход: /event auth local-test, затем /event menu. Остановка сервера: stop-server.command.'
