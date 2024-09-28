#!/bin/bash

# setup_and_start.sh
# Bash script to set up Node.js, npm, PM2, and start the Node.js server with PM2 on Ubuntu

# Exit immediately if a command exits with a non-zero status
set -e

# Function to check if a command exists
command_exists () {
    command -v "$1" >/dev/null 2>&1
}

# Function to install Node.js and npm
install_node_npm () {
    echo "Installing Node.js and npm..."
    # Install Node.js 18.x LTS from NodeSource
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
    echo "Node.js and npm installed successfully."
}

# Function to install PM2 globally
install_pm2 () {
    echo "Installing PM2 globally..."
    sudo npm install pm2@latest -g
    echo "PM2 installed successfully."
}

# Function to start or restart the Node.js server with PM2
start_pm2_process () {
    local process_name="deploy-server"
    local script_path="server.js"

    # Check if PM2 process with the given name already exists
    if pm2 list | grep -q "$process_name"; then
        echo "PM2 process '$process_name' already exists. Restarting it..."
        pm2 restart "$process_name"
    else
        echo "Starting PM2 process '$process_name'..."
        pm2 start "$script_path" --name "$process_name"
    fi

    # Save the PM2 process list
    pm2 save
}

# Function to set up PM2 to run on system startup
setup_pm2_startup () {
    echo "Setting up PM2 to run on system startup..."
    # Generate and configure the startup script
    sudo pm2 startup systemd -u "$USER" --hp "$HOME"

    # The above command outputs a command that needs to be executed.
    # We'll capture and execute it automatically.
    startup_command=$(pm2 startup systemd -u "$USER" --hp "$HOME" | grep sudo)
    if [ -n "$startup_command" ]; then
        echo "Executing PM2 startup command..."
        eval "$startup_command"
    else
        echo "Failed to retrieve PM2 startup command. Please run 'pm2 startup' manually."
        exit 1
    fi

    # Save the PM2 process list again to ensure persistence
    pm2 save
    echo "PM2 startup setup completed."
}

# Main execution flow
main () {
    echo "=== Starting Setup and PM2 Deployment Script ==="

    # Update system packages
    echo "Updating system packages..."
    sudo apt update -y
    sudo apt upgrade -y
    echo "System packages updated."

    # Install Node.js and npm if not installed
    if command_exists node && command_exists npm; then
        echo "Node.js and npm are already installed."
    else
        install_node_npm
    fi

    # Install PM2 if not installed
    if command_exists pm2; then
        echo "PM2 is already installed."
    else
        install_pm2
    fi

    # Ensure the logs directory exists
    if [ -d "logs" ]; then
        echo "'logs' directory exists."
    else
        echo "'logs' directory does not exist. Creating it..."
        mkdir logs
        echo "'logs' directory created."
    fi

    # Start or restart the Node.js server with PM2
    start_pm2_process

    # Set up PM2 to run on system startup
    setup_pm2_startup

    echo "=== Setup and PM2 Deployment Completed Successfully ==="
    echo "Your Node.js server is running under PM2 with the name 'deploy-server'."
}

# Invoke the main function
main
