#!/bin/bash

BOLD='\033[1m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'
NC='\033[0m'

command_exists() {
    command -v "$1" &> /dev/null
}

# Запрос количества валидаторов в начале скрипта
read -p "Сколько валидаторов вы хотите настроить? " num_validators

install_dependencies() {
    echo ""
    if command_exists nvm; then
        echo -e "${GREEN}NVM уже установлен.${NC}"
    else
        echo -e "${YELLOW}Установка NVM...${NC}"
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # Это загружает nvm
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # Это загружает автозаполнение для nvm
    fi

    if command_exists node; then
        echo -e "${GREEN}Node.js уже установлен: $(node -v)${NC}"
    else
        echo -e "${YELLOW}Установка Node.js...${NC}"
        nvm install node > /dev/null  # Скрываем вывод установки
        nvm use node > /dev/null  # Устанавливаем текущую версию на используемую
        echo -e "${GREEN}Node.js установлен: $(node -v)${NC}"
    fi

    echo -e "${BOLD}${CYAN}Проверка установки Docker...${NC}"
    if ! command_exists docker; then
        echo -e "${RED}Docker не установлен. Установка Docker...${NC}"
        sudo apt update && sudo apt install -y curl net-tools
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        echo -e "${GREEN}Docker успешно установлен.${NC}"
    else
        echo -e "${GREEN}Docker уже установлен.${NC}"
    fi

    # Установка необходимых библиотек для работы с SOCKS-прокси (если требуется)
    npm install socks-proxy-agent --save  # Устанавливаем socks-proxy-agent для Node.js
}

setup_validator() {
    local validator_number=$1
    
    VALIDATOR_DIR="validator_${validator_number}"
    mkdir -p $VALIDATOR_DIR
    cd $VALIDATOR_DIR

    ENV_FILE="validator.env"
    echo -e "${BOLD}${CYAN}Создание файла переменных окружения: ${VALIDATOR_DIR}/${ENV_FILE}${NC}"

    echo "ENV=testnet-3" > $ENV_FILE
    
    read -p "Введите HTTP(S) прокси для валидатора ${validator_number} (формат: IP:PORT:USERNAME:PASSWORD): " PROXY_INFO
    
    # Преобразование формата прокси в нужный формат для использования в HTTP(S)
    IFS=':' read -r PROXY_IP PROXY_PORT PROXY_USER PROXY_PASS <<< "$PROXY_INFO"
    
    PROXY_URL="http://$PROXY_USER:$PROXY_PASS@$PROXY_IP:$PROXY_PORT"
    
    echo "STRATEGY_EXECUTOR_PROXY=$PROXY_URL" >> $ENV_FILE

    read -p "Введите отображаемое имя для валидатора ${validator_number}: " DISPLAY_NAME
    echo "STRATEGY_EXECUTOR_DISPLAY_NAME=$DISPLAY_NAME" >> $ENV_FILE

    read -p "Введите адрес кошелька для получения вознаграждений валидатора ${validator_number}: " BENEFICIARY
    echo "STRATEGY_EXECUTOR_BENEFICIARY=$BENEFICIARY" >> $ENV_FILE

    read -p "Введите приватный ключ валидатора ${validator_number}: " PRIVATE_KEY
    echo "SIGNER_PRIVATE_KEY=$PRIVATE_KEY" >> $ENV_FILE

    echo ""
    echo -e "${BOLD}${CYAN}Файл ${VALIDATOR_DIR}/${ENV_FILE} был создан со следующим содержимым:${NC}"
    cat $ENV_FILE
    echo ""

    UNIQUE_PORT=$((17690 + validator_number))
    
    # Запуск Docker для валидатора с учетом ошибок
    echo -e "${BOLD}${CYAN}Запуск Docker для валидатора ${validator_number}...${NC}"
    
    docker run -d --env-file $ENV_FILE --name elixir-$DISPLAY_NAME \
      -e HTTP_PROXY="$PROXY_URL" \
      -e HTTPS_PROXY="$PROXY_URL" \
      -v "$(pwd):/app/data" \
      -p $UNIQUE_PORT:17690 --restart unless-stopped elixirprotocol/validator:v3
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Валидатор ${validator_number} успешно запущен.${NC}"
    else
        echo -e "${RED}Ошибка при запуске валидатора ${validator_number}.${NC}"
    fi

    cd ..
}

main() {
     # Установка зависимостей перед настройкой валидаторов.
     install_dependencies

     # Загрузка образа валидатора Elixir Protocol перед настройкой.
     echo -e "${BOLD}${CYAN}Загрузка образа валидатора Elixir Protocol...${NC}"

     docker pull elixirprotocol/validator:v3

     INITIAL_DIR=$(pwd)

     for ((i=1; i<=num_validators; i++))
     do
         setup_validator $i
     done

     cd $INITIAL_DIR

     echo ""
     echo -e "${BOLD}${CYAN}Выполнение скрипта завершено успешно.${NC}"
     echo -e "${YELLOW}Не забудьте проверить статус ваших валидаторов и настроить мониторинг.${NC}"
}

# Запуск основной функции скрипта.
main