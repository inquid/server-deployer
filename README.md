# Deploy Server Project

![Project Logo](https://via.placeholder.com/150)

## Table of Contents

- [Deploy Server Project](#deploy-server-project)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Features](#features)
  - [Prerequisites](#prerequisites)
  - [Usage](#usage)
  - [Trigger a Deployment via API:](#trigger-a-deployment-via-api)

---

## Overview

The **Deploy Server Project** is a robust Node.js application designed to manage and automate deployment processes using a combination of Express.js, PM2, and Bash scripting. It provides a RESTful API to trigger deployments and monitor their status, ensuring efficient and reliable application updates.

## Features

- **Automated Deployments:** Trigger deployments via API endpoints.
- **Process Management:** Uses PM2 to manage the Node.js server, ensuring high availability and automatic restarts.
- **Comprehensive Logging:** Maintains detailed logs of deployment processes for easy monitoring and troubleshooting.
- **System Setup Script:** A single Bash script to install necessary dependencies (Node.js, npm, PM2) and configure the server.
- **Git Ignorance:** Configured `.gitignore` to track only essential files, keeping the repository clean.

## Prerequisites

Before setting up the project, ensure your system meets the following requirements:

- **Operating System:** Ubuntu 18.04 or later
- **User Permissions:** Ability to run commands with `sudo`
- **Existing `logs` Directory:** The `logs` directory should exist in the project root

## Usage

```
wget https://github.com/inquid/server-deployer/archive/refs/heads/main.zip

unzip main.zip

cd server-deployer-main

chmod +x scripts/setup_and_start.sh
chmod +x scripts/deployer.sh

./scripts/setup_and_start.sh
```

When live you can do

```
curl http://localhost:3000/
```

Response
```
Deployer service available
```

## Trigger a Deployment via API:

Use curl or any API client (like Postman) to send a POST request.


```bash
curl -X POST http://localhost:3000/deploy \
     -H "Content-Type: application/json" \
     -d '{
         "dockerImage": "vendor/image-staging:latest",
         "domain": "yourdomain.com",
         "containerName": "app_container",
         "s3Bucket": "app-container-bucket"
     }'
```



Check Deployment Status:


```
curl http://localhost:3000/status
```

```
wget https://github.com/inquid/server-deployer/archive/refs/heads/main.zip
sudo apt install unzip
unzip main.zip
cd server-deployer-main
chmod +x scripts/setup_and_start.sh                                       
chmod +x scripts/deployer.sh
sudo ./scripts/setup_and_start.sh
```
