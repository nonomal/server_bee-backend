#!/bin/bash

# Define colors
INFO='\033[1;34m'
WARNING='\033[1;33m'
ERROR='\033[1;31m'
NC='\033[0m' # No Color

# Declare variables
use_external_mongo=""
MONGO_INITDB_ROOT_USERNAME=""
MONGO_INITDB_ROOT_PASSWORD=""
MONGODB_URI=""
NEXTAUTH_SECRET=""
SERVER_JWT_SECRET=""
SERVER_TOKEN=""
RECORDER_DOMAIN=""

# Function to check system type
check_system_type() {
    if [[ "$(uname)" == "Linux" ]]; then
        echo -e "${INFO}Linux system detected.${NC}"
    elif [[ "$(uname)" == "Darwin" ]]; then
        echo -e "${INFO}Mac system detected.${NC}"
    else
        echo -e "${ERROR}Unsupported system type.${NC}"
        echo -e "${ERROR}Please install manually.${NC}"
        exit 1
    fi
}

check_tools_installed() {
    # Function to check if OpenSSL is installed
    if ! command -v openssl &>/dev/null; then
        echo -e "${WARNING}OpenSSL is not installed.${NC}"
        echo -e "${WARNING}Please install OpenSSL manually.${NC}"
    else
        echo -e "${INFO}OpenSSL is already installed.${NC}"
    fi

    # Check if git is installed
    if ! command -v git &>/dev/null; then
        echo -e "${WARNING}Git is not installed.${NC}"
        echo -e "${WARNING}Please install Git manually.${NC}"
    else
        echo -e "${INFO}Git is already installed.${NC}"
    fi
}

# Function to write values to .env file
write_to_env_file() {
    local nextauth_secret=$1
    local mongo_initdb_root_username=$2
    local mongo_initdb_root_password=$3
    local mongodb_uri=$4
    local server_jwt_secret=$5
    local server_token=$6

    cat <<EOF >.env
RUST_LOG=waring
DATABASE_URL="file:/app/serverhub.db"
NEXTAUTH_SECRET="${nextauth_secret}"
NEXTAUTH_URL="hub:3000"
MONGO_INITDB_ROOT_USERNAME="${mongo_initdb_root_username}"
MONGO_INITDB_ROOT_PASSWORD="${mongo_initdb_root_password}"
MONGODB_URI="${mongodb_uri}"
SERVER_JWT_SECRET="${server_jwt_secret}"
SALT_ROUNDS=10
AUTH_SERVER_URL="hub:3000/api/user/auth"
SERVICE_URL="hub:3000/api/server"
SERVER_HOST="recorder:9528"
SERVER_TOKEN="${server_token}"
EOF
}

# Function to set MongoDB variables
set_mongo_variables() {
    read -p "Will you be using an external MongoDB service? (y/n): " use_external_mongo

    use_external_mongo=${use_external_mongo:-n}
    use_external_mongo=$(echo "$use_external_mongo" | tr '[:upper:]' '[:lower:]')

    if [[ $use_external_mongo == "n" ]]; then
        # Generate random values for MONGO_INITDB_ROOT_USERNAME and MONGO_INITDB_ROOT_PASSWORD
        MONGO_INITDB_ROOT_USERNAME=$(openssl rand -base64 12 | tr -d '/@:')
        MONGO_INITDB_ROOT_PASSWORD=$(openssl rand -base64 12 | tr -d '/@:')

        # Update MONGODB_URI with the generated values
        MONGODB_URI="mongodb://${MONGO_INITDB_ROOT_USERNAME}:${MONGO_INITDB_ROOT_PASSWORD}@mongo:27017/"
    else
        # Prompt user for MONGODB_URI
        echo -e "${WARNING}Enter the MongoDB URI:${NC}"
        read MONGODB_URI

        # Remove MONGO_INITDB_ROOT_USERNAME and MONGO_INITDB_ROOT_PASSWORD
        unset MONGO_INITDB_ROOT_USERNAME
        unset MONGO_INITDB_ROOT_PASSWORD
    fi
}

# Function to set Caddy configuration
write_to_caddy_file() {
    local recorder_domain=$1

    cat <<EOF >Caddyfile
{
    auto_https off
}

:80, :443 {
    @recorder host $recorder_domain
    reverse_proxy @recorder recorder:9528

    route /api/i/* {
        uri strip_prefix /api/i
        reverse_proxy interactor:9529
    }

    reverse_proxy hub:3000
}
EOF
}

installation() {
    # Prompt user to start installation
    echo -e "${INFO}Starting application installation...${NC}"

    # Call the function to set MongoDB variables
    set_mongo_variables

    echo -e "${WARNING}Enter the recorder domain (Example: recorder.serverhub.app):${NC}"
    read RECORDER_DOMAIN
    echo -e "${INFO}Make sure to ${RECORDER_DOMAIN} point to the server IP address.${NC}"
    read -p "Press Enter to continue..."

    # Generate random values
    NEXTAUTH_SECRET=$(openssl rand -base64 32)
    SERVER_JWT_SECRET=$(openssl rand -base64 32)
    SERVER_TOKEN=$(openssl rand -base64 32)

    # Function to print and confirm user input variables
    print_and_confirm_variables() {
        echo -e "${INFO}Please reconfirm input variable:${NC}"
        echo -e "========================================================"
        if [[ -n $MONGO_INITDB_ROOT_USERNAME ]]; then
            echo -e "${INFO}MONGO_INITDB_ROOT_USERNAME:${NC} ${WARNING}$MONGO_INITDB_ROOT_USERNAME${NC}"
        fi
        if [[ -n $MONGO_INITDB_ROOT_PASSWORD ]]; then
            echo -e "${INFO}MONGO_INITDB_ROOT_PASSWORD:${NC} ${WARNING}$MONGO_INITDB_ROOT_PASSWORD${NC}"
        fi
        echo -e "${INFO}MONGODB_URI:${NC} ${WARNING}$MONGODB_URI${NC}"
        echo -e "${INFO}NEXTAUTH_SECRET:${NC} ${WARNING}$NEXTAUTH_SECRET${NC}"
        echo -e "${INFO}SERVER_JWT_SECRET:${NC} ${WARNING}$SERVER_JWT_SECRET${NC}"
        echo -e "${INFO}SERVER_TOKEN:${NC} ${WARNING}$SERVER_TOKEN${NC}"
        echo -e "${INFO}RECORDER_DOMAIN:${NC} ${WARNING}$RECORDER_DOMAIN${NC}"
        echo -e "========================================================"

        # Ask user for confirmation
        read -p "Are the variables correct? (y/n): " confirm_variables

        if [[ $confirm_variables != "y" ]]; then
            echo -e "${ERROR}Installation aborted.${NC}"
            exit 1
        fi
    }

    # Call the function to print and confirm variables
    print_and_confirm_variables

    # Clone GitHub repository
    git clone https://github.com/ZingerLittleBee/server_bee-backend.git
    cd server_bee-backend/docker || exit

    # Call the function to set Caddy configuration
    write_to_caddy_file "$RECORDER_DOMAIN"

    # Write the generated values to .env file using the function
    write_to_env_file "$NEXTAUTH_SECRET" "$MONGO_INITDB_ROOT_USERNAME" "$MONGO_INITDB_ROOT_PASSWORD" "$MONGODB_URI" "$SERVER_JWT_SECRET" "$SERVER_TOKEN"

    if [[ $use_external_mongo == "y" ]]; then
        sed -i '/[ \t]*mongo/,/[ \t]*hub/{/[ \t]*hub/!d}' docker-compose.yml
    fi

    docker-compose up -d
}

uninstallation() {
    echo -e "${WARNING}Starting application uninstallation...${NC}"

    cd server_bee-backend/docker || exit

    docker-compose down

    echo -e "${ERROR}Whether to remove all data? (y/n)${NC}"
    read confirm_remove_data

    if [[ $confirm_remove_data == "y" ]]; then
        cd ../..
        rm -rf server_bee-backend
    fi

    echo -e "${INFO}Uninstallation completed.${NC}"
}

update() {
    echo -e "${INFO}Starting application update...${NC}"

    if [[ -f docker-compose.yml ]]; then
        cd ../..
    fi

    cd server_bee-backend || exit

    git pull

    cd docker || exit

    docker-compose down

    docker-compose up -d

    echo -e "${INFO}Update completed.${NC}"
}

status() {
    echo -e "${INFO}Checking application status...${NC}"

    # check docker ps status in the server_bee-backend/docker directory or the current directory
    if [[ ! -f docker-compose.yml ]]; then
        cd server_bee-backend/docker || exit
    fi

    docker-compose ps

    echo "Select service to check logs:"
    options=("serverhub" "serverbee-recorder" "serverbee-interactor" "serverbee-web" "serverbee-caddy" "serverbee-mongo" "back")
    select opt in "${options[@]}"; do
        case $opt in
        "serverhub")
            docker logs serverhub
            ;;
        "serverbee-recorder")
            docker logs serverbee-recorder
            ;;
        "serverbee-interactor")
            docker logs serverbee-interactor
            ;;
        "serverbee-web")
            docker logs serverbee-web
            ;;
        "serverbee-caddy")
            docker logs serverbee-caddy
            ;;
        "serverbee-mongo")
            docker logs serverbee-mongo
            ;;
        "back")
            break
            ;;
        *) echo "Invalid selection, please try again" ;;
        esac
    done

}

check_system_type
check_tools_installed

echo "Welcome to use ServerHub automatic installation, please select an option:"
options=("Installation" "Update" "Uninstallation" "Status" "Exit")
select opt in "${options[@]}"; do
    case $opt in
    "Installation")
        installation
        ;;
    "Update")
        update
        ;;
    "Uninstallation")
        uninstallation
        ;;
    "Status")
        status
        ;;
    "Exit")
        break
        ;;
    *) echo "Invalid selection, please try again" ;;
    esac
done