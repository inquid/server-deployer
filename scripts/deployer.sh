#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Function to display usage
usage() {
    echo "Usage: $0 --container-name <name> --image-name <image> --s3-bucket <bucket> --domain-name <domain>"
    exit 1
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --container-name)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        --image-name)
            IMAGE_NAME="$2"
            shift 2
            ;;
        --s3-bucket)
            S3_BUCKET="$2"
            shift 2
            ;;
        --domain-name)
            DOMAIN_NAME="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter passed: $1"
            usage
            ;;
    esac
done

# Check if all required parameters are provided
if [ -z "$CONTAINER_NAME" ] || [ -z "$IMAGE_NAME" ] || [ -z "$S3_BUCKET" ] || [ -z "$DOMAIN_NAME" ]; then
    echo "Error: Missing required parameters."
    usage
fi

CERT_PATH="nginx/$DOMAIN_NAME/letsencrypt"
CONF_PATH="nginx/$DOMAIN_NAME/conf/default.conf"

echo "Starting deployment with the following parameters:"
echo "Container Name: $CONTAINER_NAME"
echo "Image Name: $IMAGE_NAME"
echo "S3 Bucket: $S3_BUCKET"
echo "Domain Name: $DOMAIN_NAME"

# Update and upgrade system packages
sudo apt update && sudo apt upgrade -y

# Install unzip if not present
sudo apt install -y unzip

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI not found, installing AWS CLI..."
    # Download the AWS CLI installation file
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    
    # Unzip the installation file
    unzip awscliv2.zip
    
    # Install the AWS CLI
    sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
    
    # Clean up
    rm -rf awscliv2.zip aws/
else
    echo "AWS CLI is already installed."
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity --profile default >/dev/null 2>&1; then
    echo "AWS CLI is not configured. Configuring AWS CLI..."
    # AWS credentials and region (Assuming they are set as environment variables)
    aws configure set aws_access_key_id "${AWS_ACCESS_KEY_ID:-default_access_key}" --profile default
    aws configure set aws_secret_access_key "${AWS_SECRET_ACCESS_KEY:-default_secret_key}" --profile default
    aws configure set region "${AWS_REGION:-us-east-1}" --profile default
    aws configure set output "${AWS_OUTPUT:-json}" --profile default
else
    echo "AWS CLI is already configured."
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Docker not found, installing Docker..."
    sudo apt install -y ca-certificates curl gnupg lsb-release
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
    echo "Docker is already installed."
fi

# Check Docker version
docker -v

# Stop and remove the container if it exists
echo "Stopping and removing the container if it exists..."
if [ "$(docker ps -a -q -f name=^/${CONTAINER_NAME}$)" ]; then
    docker stop "$CONTAINER_NAME" && docker rm "$CONTAINER_NAME"
else
    echo "Container $CONTAINER_NAME does not exist."
fi

# Delete all unused Docker images
echo "Deleting all unused Docker images..."
docker image prune -af

# Log in to Docker using AWS ECR credentials
echo "Logging in to Docker with AWS ECR credentials..."
aws ecr get-login-password --region us-east-1 --profile default | docker login --username AWS --password-stdin "$(echo $IMAGE_NAME | cut -d'/' -f1)"

# Pull the latest image
echo "Pulling the latest Docker image..."
docker pull "$IMAGE_NAME"

# Run the container with specified ports and environment variables
echo "Running the container..."
docker run -p 80:80 -p 443:443 -p 1080:1080 -p 3306:3306 -p 1025:1025 -p 8888:88 -p 8080:8080 \
-e MYSQL_ROOT_PASSWORD="$DB_PASSWORD" \
-e MYSQL_DATABASE="$CONTAINER_NAME" \
-e MYSQL_USER="$CONTAINER_NAME"_user \
-e MYSQL_PASSWORD="$DB_PASSWORD" \
--name "$CONTAINER_NAME" -d "$IMAGE_NAME"

# Wait for the MySQL server to be ready
echo "Waiting for MySQL server to start..."
sleep 10

# Check if the database exists, and create it if it doesn't
echo "Checking if the database exists..."
docker exec -i "$CONTAINER_NAME" mysql -u root -p"$DB_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"

# Run the Laravel commands
echo "Entering the container and running the Laravel commands..."
docker exec -i "$CONTAINER_NAME" bash -c "php artisan db:wipe && php artisan migrate --force --seed"

# Check if certificate exists in S3
echo "Checking if the SSL certificate and Nginx configuration exist in S3..."
CERT_EXISTS=$(aws s3 ls "s3://$S3_BUCKET/$CERT_PATH/" --profile default)
CONF_EXISTS=$(aws s3 ls "s3://$S3_BUCKET/$CONF_PATH" --profile default)

if [ -z "$CERT_EXISTS" ] || [ -z "$CONF_EXISTS" ]; then
    echo "Certificate or Nginx config not found, generating a new certificate using Certbot..."
    # Add certbot to the container and generate the certificate
    docker exec -i "$CONTAINER_NAME" /bin/sh -c "apk add certbot certbot-nginx"
    docker exec -i "$CONTAINER_NAME" certbot --nginx -d "$DOMAIN_NAME" --email developer@bluestudio.mx --agree-tos --no-eff-email --non-interactive
    
    # Copy the generated certificates back to S3 for future use
    echo "Uploading generated certificates to S3..."
    docker cp "$CONTAINER_NAME":/etc/letsencrypt /home/ubuntu/letsencrypt
    aws s3 cp /home/ubuntu/letsencrypt "s3://$S3_BUCKET/$CERT_PATH/" --recursive --profile default
    
    # Backup the nginx configuration as well
    docker cp "$CONTAINER_NAME":/etc/nginx/conf.d/default.conf /home/ubuntu/nginx/default.conf
    aws s3 cp /home/ubuntu/nginx/default.conf "s3://$S3_BUCKET/$CONF_PATH" --profile default
else
    echo "Certificate and Nginx config found in S3, downloading..."
    # Copy the letsencrypt folder from S3 to the host
    aws s3 cp "s3://$S3_BUCKET/$CERT_PATH" /home/ubuntu/letsencrypt --recursive --profile default
    
    # Copy the letsencrypt folder from the host to the container
    docker cp /home/ubuntu/letsencrypt "$CONTAINER_NAME":/etc/letsencrypt
    
    # Copy the nginx configuration file from S3 to the host
    aws s3 cp "s3://$S3_BUCKET/$CONF_PATH" /home/ubuntu/nginx/default.conf --profile default
    
    # Copy the nginx configuration file from the host to the container
    docker cp /home/ubuntu/nginx/default.conf "$CONTAINER_NAME":/etc/nginx/conf.d/default.conf
fi

# Restart Nginx inside the container
docker exec "$CONTAINER_NAME" sh -c "nginx -s reload || (pkill nginx && nginx)"

# Download the credentials file from S3 to the host
echo "Downloading the credentials file from S3..."
aws s3 cp "s3://$S3_BUCKET/credentials/firebase_credentials.json" ./firebase_credentials.json --profile default

# Copy the credentials file into the Docker container
echo "Copying the credentials file into the Docker container..."
docker cp ./firebase_credentials.json "$CONTAINER_NAME":/var/www/html/credentials/

# Clean up the downloaded file
rm ./firebase_credentials.json

echo "Script execution completed."
