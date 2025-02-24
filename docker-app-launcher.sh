#!/bin/bash

# Check if at least one command-line argument is provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 PROJECT_NAME"
    exit 1
fi

# Set the first parameter as PROJECT_NAME
PROJECT_NAME=$1

# =================================================================
# 鎖定

lock_file_path="/tmp/docker-app/${PROJECT_NAME}.lock"

if [ -e "$lock_file_path" ]; then
    # Get the creation time of the file in seconds since epoch
    file_creation_time=$(stat -c %W "$lock_file_path")
    current_time=$(date +%s)
    timeout_seconds=600

    #if [ $((current_time - file_creation_time)) -gt $timeout_seconds ]; then
        # rm "$lock_file_path"
    #fi
fi

# =================================================================

if [ -e "$lock_file_path" ]; then
    parameters=("${@:3}")
    # Read each line from the lock file
    while IFS= read -r line; do
        # Check if the line matches the parameters
        if [ "$line" == "$parameters" ]; then
            echo "Parameters already exist in the lock file. Exiting..."
            exit 0
        fi
    done < "$lock_file_path"
    echo $parameters >> "${lock_file_path}"
    echo "Added queue ${parameters}"
    exit 0
else
    echo "Lock file does not exist."
fi

# =================================================================

mkdir -p /tmp/docker-app/
touch "${lock_file_path}"

# =================================================================
# 宣告函數

openURL() {
  url="$1"
  echo "${url}"

  if command -v xdg-open &> /dev/null; then
    xdg-open "${url}" &
  elif command -v open &> /dev/null; then
    open "${url}" &
  fi
}

getRealpath() {
  path="$1"

  if [[ $path == /* || -z $path ]]; then
    #echo "$path"
    :
  elif command -v realpath &> /dev/null; then
    path=`realpath "${path}"`
  else
    path=$(cd "$(dirname "${path}")"; pwd)/"$(basename "${path}")"
  fi
  echo "${path}"
}

# ========

getExtPort() {
  local ext_port

  #cat "/tmp/docker-app/docker-web-ext-port.txt"

  # Check if the file exists
  if [ -f "/tmp/docker-app/docker-web-ext-port.txt" ]; then
    # Read ext_port from the file
    ext_port=$(<"/tmp/docker-app/docker-web-ext-port.txt")
    # Check if ext_port is occupied, and if it is, increment it until it's available

    while docker ps | grep -q ":$ext_port->"; do
      ext_port=$((ext_port + 1))
      if [ "$ext_port" -gt 59999 ]; then
        ext_port=50000
        break
      fi
    done

    while nc -z localhost "$ext_port"; do
      ext_port=$((ext_port + 1))
      if [ "$ext_port" -gt 59999 ]; then
        ext_port=50000
        break
      fi
    done

    # Save ext_port to the file
    echo "$ext_port" > "/tmp/docker-app/docker-web-ext-port.txt"

    # Return ext_port
    echo "${ext_port}"
  else
    # If the file does not exist, set ext_port to 50000
    ext_port=50000
    echo "$ext_port" > "/tmp/docker-app/docker-web-ext-port.txt"
    echo "${ext_port}"
  fi
}

# ------------------
# 確認環境

# Get the directory path of the script
SCRIPT_PATH=$(getRealpath "$2")

# SCRIPT_PATH=$(getRealpath "${SCRIPT_PATH}")

# echo "PWD: ${SCRIPT_PATH}"

# ------------------

if ! command -v git &> /dev/null
then
  echo "git could not be found"

  openURL https://git-scm.com/downloads &

  if [ -e "${lock_file_path}" ]; then
    rm "${lock_file_path}"
  fi

  exit 1
fi

if ! command -v docker-compose &> /dev/null
then
  echo "docker-compose could not be found"

  openURL https://docs.docker.com/compose/install/ &

  if [ -e "${lock_file_path}" ]; then
    rm "${lock_file_path}"
  fi

  exit 1
fi

# ---------------
# 安裝或更新專案

project_inited=false
if [ -d "/tmp/docker-app/${PROJECT_NAME}" ];
then
  cd "/tmp/docker-app/${PROJECT_NAME}"

  git reset --hard
  git pull --force
else
  project_inited=true
	# echo "$DIR directory does not exist."
  mkdir -p /tmp/docker-app/
  cd /tmp/docker-app/
  git clone "https://github.com/pulipulichen/${PROJECT_NAME}.git"
  cd "/tmp/docker-app/${PROJECT_NAME}"
fi

# -----------------
# 確認看看要不要做docker-compose build

mkdir -p "/tmp/docker-app/${PROJECT_NAME}.cache"

cmp --silent "/tmp/docker-app/${PROJECT_NAME}/Dockerfile" "/tmp/docker-app/${PROJECT_NAME}.cache/Dockerfile" && cmp --silent "/tmp/docker-app/${PROJECT_NAME}/package.json" "/tmp/docker-app/${PROJECT_NAME}.cache/package.json" || docker-compose build

cp "/tmp/docker-app/${PROJECT_NAME}/Dockerfile" "/tmp/docker-app/${PROJECT_NAME}.cache/"
cp "/tmp/docker-app/${PROJECT_NAME}/package.json" "/tmp/docker-app/${PROJECT_NAME}.cache/"

# =================
# 從docker-compose-template.yml來判斷參數

INPUT_FILE="false"
if [ -f "/tmp/docker-app/${PROJECT_NAME}/docker-build/image/docker-compose-template.yml" ]; then
  if grep -q "__INPUT__" "/tmp/docker-app/${PROJECT_NAME}/docker-build/image/docker-compose-template.yml"; then
    INPUT_FILE="true"
  fi
fi

# --------

# Using grep and awk to extract the public port from the docker-compose.yml file
PUBLIC_PORT="false"
# Step 2: Read the public port from the docker-compose.yml file
# DOCKER_COMPOSE_FILE="/tmp/docker-app/${PROJECT_NAME}/docker-compose.yml"

# # Check if the default Docker Compose file exists
# if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
#   # If the file doesn't exist, set an alternative file path
#   DOCKER_COMPOSE_FILE="/tmp/docker-app/${PROJECT_NAME}/docker-build/image/docker-compose-template.yml"
# fi
DOCKER_COMPOSE_FILE="/tmp/docker-app/${PROJECT_NAME}/docker-build/image/docker-compose-template.yml"
if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
  # If the file doesn't exist, set an alternative file path
  DOCKER_COMPOSE_FILE="/tmp/docker-app/${PROJECT_NAME}/docker-compose.yml"
fi

if [ -f "$DOCKER_COMPOSE_FILE" ]; then
  #PUBLIC_PORT=$(awk '/ports:/{flag=1} flag && /- "[0-9]+:[0-9]+"/{split($2, port, ":"); gsub(/"/, "", port[1]); print port[1]; flag=0}' "$DOCKER_COMPOSE_FILE")
  echo "/tmp/docker-app/${PROJECT_NAME}/docker-build/image/docker-compose-template.yml"
  template=$(cat "/tmp/docker-app/${PROJECT_NAME}/docker-build/image/docker-compose-template.yml")
  echo $template
  if [[ $template == *__EXT_PORT__* ]]; then
    PUBLIC_PORT=$(getExtPort)
    PUBLIC_PORT="${PUBLIC_PORT%%$'\n'*}"
  else
    PUBLIC_PORT=$(awk '/ports:/{flag=1} flag && /- "[0-9]+:[0-9]+"/{split($2, port, ":"); gsub(/"/, "", port[1]); print port[1]; flag=0}' "$DOCKER_COMPOSE_FILE")
  fi
fi
if [ "${PUBLIC_PORT}" == "" ]; then
  PUBLIC_PORT="false"
fi

# =================
# 讓Docker能順利運作的設定
# Linux跟Mac需要

if [ -z "$DOCKER_HOST" ]; then

    if [[ "$(uname)" == "Darwin" ]]; then
      echo "Running on macOS"
    else
      echo "DOCKER_HOST is not set, setting it to 'unix:///run/user/1000/docker.sock'"
      export DOCKER_HOST="unix:///run/user/1000/docker.sock"
    fi
else
    echo "DOCKER_HOST is set to '$DOCKER_HOST'"
fi

# -------------------
# 檢查有沒有輸入檔案參數

var="$3"
var=$(getRealpath "${var}")
echo "========"
echo $var
echo "========"
useParams="true"
WORK_DIR=`pwd`
if [ "$INPUT_FILE" != "false" ]; then
  if [ ! -e "$var" ]; then
    # echo "$1 does not exist."
    # exit
    if command -v kdialog &> /dev/null; then
      var=$(kdialog --getopenfilename --multiple ~/ 'Files')

    elif command -v osascript &> /dev/null; then
      selected_file="$(osascript -l JavaScript -e 'a=Application.currentApplication();a.includeStandardAdditions=true;a.chooseFile({withPrompt:"Please select a file to process:"}).toString()')"

      # Storing the selected file path in the "var" variable
      var="$selected_file"

    fi
    var=`echo "${var}" | xargs`
    useParams="false"
  fi
fi

# =================================================================
# 宣告函數

dirname=$(dirname "$SCRIPT_PATH")
cloudflare_file="${dirname}/${PROJECT_NAME}/.cloudflare.url"
cloudflare_file_app="/tmp/docker-app/${PROJECT_NAME}/app/.cloudflare.url"

getCloudflarePublicURL() {


  # echo "c ${cloudflare_file}"

  # Wait until the file exists
#   while [ ! -f "$cloudflare_file" ]; do
#     # echo "not exists ${cloudflare_file}"
#     sleep 1  # Check every 1 second
#   done
  timeout=60
  interval=5
  elapsed_time=0

  while [ $elapsed_time -lt $timeout ]; do
    if [ -s "$cloudflare_file" ] && [ -f "$cloudflare_file" ]; then
        echo $(<"$cloudflare_file")
        exit 0
    fi

    if [ -s "$cloudflare_file_app" ] && [ -f "$cloudflare_file_app" ]; then
        echo $(<"$cloudflare_file_app")
        exit 0
    fi

    sleep $interval
    elapsed_time=$((elapsed_time + interval))
  done

  #echo "false"
  #exit 1
}

# ----------------------------------------------------------------

setDockerComposeYML() {
  file="$1"
  #echo "input: ${file}"

  filename=$(basename "$file")
  dirname=$(dirname "$file")
  dirname=$(echo "$dirname" | tail -n 1)


  echo "/tmp/docker-app/${PROJECT_NAME}/docker-build/image/docker-compose-template.yml"
  template=$(cat "/tmp/docker-app/${PROJECT_NAME}/docker-build/image/docker-compose-template.yml")
  #echo "$template"
  if [ -z "$template" ]; then
    echo "Template error"
    rm -rf "$lock_file_path"
    exit 1
  fi

  # template=$(echo "$template" | sed "s/__SOURCE__/$dirname/g")
  # template=$(echo "$template" | sed "s/__INPUT__/$filename/g")

  if [[ "$template" == *__EXT_PORT__* ]]; then
    result="${PUBLIC_PORT}"

#     echo "result: ${result}"
    # template=$(echo "$template" | sed "s|__EXT_PORT__|\"${result}\"|g") || echo "result: ${result}"
    template="${template//__EXT_PORT__/${result}}" || echo "result: ${result}"
  fi
  if [[ "$template" == *__NETWORK__* ]]; then
    result="${PUBLIC_PORT}"

#     echo "result: ${result}"
    # template=$(echo "$template" | sed "s|__EXT_PORT__|\"${result}\"|g") || echo "result: ${result}"
    template="${template//__NETWORK__/docker_web_network_${result}}" || echo "docker_web_network_result: docker_web_network_${result}"
  fi
  if [[ "$template" == *__SOURCE__* ]]; then
    #echo "dirname: ${dirname}"
    #template=$(echo "$template" | sed "s|__SOURCE__|$dirname|g")
    template="${template//__SOURCE__/${dirname}}" || echo "dirname SOURCE: ${dirname}"
  fi
  if [[ "$template" == *__SOURCE_INPUT__* ]]; then
    # echo "dirname: ${dirname}"
    # template=$(echo "$template" | sed "s|__SOURCE_INPUT__|$dirname|g")
    template="${template//__SOURCE_INPUT__/${dirname}}" || echo "dirname SOURCE_INPUT: ${dirname}"
  fi
  if [[ "$template" == *__SOURCE_APP__* ]]; then
    template=$(echo "$template" | sed "s|__SOURCE_APP__|/tmp/docker-app/${PROJECT_NAME}/app|g")
  fi
  if [[ "$template" == *__INPUT__* ]]; then
    filename=$(echo "$filename" | sed 's/&/\\&/g')
    echo $filename
    template=$(echo "$template" | sed "s|__INPUT__|$filename|g")
  fi

  echo "$template" > "/tmp/docker-app/${PROJECT_NAME}/docker-compose.yml"

  if [ -z "$template" ]; then
    echo "Template error"
    rm -rf "$lock_file_path"
    exit 1
  fi

}


# ========

waitForConntaction() {
  port="$1"
  sleep 3
  while true; do
    if curl -sSf "http://127.0.0.1:$port" >/dev/null 2>&1; then
      echo "Connection successful."
      break
    else
      echo "Connection failed (${port}) . Retrying in 5 seconds..."
      sleep 5
    fi
  done
}

runDockerCompose() {
  must_sudo="false"
  if [[ "$(uname)" == "Darwin" ]]; then
    if ! chown -R $(whoami) ~/.docker; then
      sudo chown -R $(whoami) ~/.docker
      must_sudo="true"
      # exit 0
    fi
  fi

  file="$1"

  #echo "m ${must_sudo}"

  if [ "$PUBLIC_PORT" == "false" ]; then
    if [ "$must_sudo" == "false" ]; then
      docker-compose down
      if ! docker-compose up --build; then
        echo "Error occurred. Trying with sudo..."
        sudo docker-compose down
        sudo docker-compose up --build

        # sudo chmod 777 -R "$file"
      fi
    else
      sudo docker-compose down
      sudo docker-compose up --build

      # sudo chmod 777 -R "$file"
    fi
    # exit 0
  else
    # Set up a trap to catch Ctrl+C and call the cleanup function
    trap 'cleanup' INT

    if [ "$must_sudo" == "false" ]; then
      docker-compose down
      if ! docker-compose up --build -d; then
        echo "Error occurred. Trying with sudo..."
        sudo docker-compose down
        sudo docker-compose up --build -d
      fi
    else
      sudo docker-compose down
      sudo docker-compose up --build -d
    fi

    waitForConntaction $PUBLIC_PORT

    cloudflare_url=$(getCloudflarePublicURL)
    # cloudflare_url=$(<"${SCRIPT_PATH}/${PROJECT_NAME}/.cloudflare.url")

    sleep 10
    #/tmp/.cloudflared --url "http://127.0.0.1:$PUBLIC_PORT" > /tmp/.cloudflared.out

    echo "================================================================"
    echo "You can link the website via following URL:"
    echo ""


    # openURL "http://127.0.0.1:$PUBLIC_PORT"
    # echo "${cloudflare_url}"
    if { [ -z "$cloudflare_url" ] || [ "$cloudflare_url" == "false" ]; } && [ project_inited == true ]; then
      openURL "http://127.0.0.1:$PUBLIC_PORT"
    else
      openURL "${cloudflare_url}"
      echo "http://127.0.0.1:$PUBLIC_PORT"
    fi

    echo ""
    # Keep the script running to keep the container running
    # until the user decides to stop it
    echo "Press Ctrl+C to stop the Docker container and exit."
    echo "================================================================"

    # Wait indefinitely, simulating a long-running process
    # This is just to keep the script running until the user interrupts it
    # You might replace this with an actual running process that should keep the script alive
    while true; do
      sleep 1
    done
  fi
}

# Function to handle clean-up on script exit or Ctrl+C
cleanup() {
  echo "Stopping the Docker container..."
  docker-compose down
  if [ -f "${lock_file_path}" ]; then
    rm "${lock_file_path}"
  fi
  exit 1
}

# -----------------
# 執行指令

if [ "$INPUT_FILE" != "false" ]; then
  if [ "${useParams}" == "true" ]; then
    # echo "use parameters"
    PARAMETERS=("${@:3}")
    for var in "${PARAMETERS[@]}"; do
      cd "${WORK_DIR}"

      if [ -f "${var}" ]; then
        var=$(getRealpath "${var}")
      fi
      cd "/tmp/docker-app/${PROJECT_NAME}"

      setDockerComposeYML "${var}"
      runDockerCompose "${var}"
    done
  else
    if [ ! -f "${var}" ]; then
      echo "$var does not exist."
    else
      setDockerComposeYML "${var}"

      runDockerCompose "${var}"
    fi
  fi
else
  cd "/tmp/docker-app/${PROJECT_NAME}"

  # echo "PWD: ${SCRIPT_PATH}"
  setDockerComposeYML "${SCRIPT_PATH}"

  # cat "/tmp/${PROJECT_NAME}/docker-compose.yml"
  # exit 0
  rm -f "${cloudflare_file}"
  runDockerCompose "${SCRIPT_PATH}"
fi

# =================================================================
# 解除鎖定

# Check if the lock file exists and is not empty
while [ -s "$lock_file_path" ]; do
  # Get the first line as the parameter
  parameters=$(head -n 1 "$lock_file_path")
  # Remove the first line from the lock file
  tail -n +2 "$lock_file_path" > "$lock_file_path.tmp" && mv "$lock_file_path.tmp" "$lock_file_path"

  # =================================================================
  if [ ! "${parameters}" == "" ]; then

    cd "${WORK_DIR}"

    if [ -f "${parameters}" ]; then
      parameters=$(getRealpath "${parameters}")
    fi
    cd "/tmp/docker-app/${PROJECT_NAME}"

    setDockerComposeYML "${parameters}"
    runDockerCompose
  fi
done

# =================================================================
# 移除鎖

echo "Lock file is empty or does not exist. Removing and exiting..."
if [ -e "${lock_file_path}" ]; then
  rm "${lock_file_path}"
fi
exit 0