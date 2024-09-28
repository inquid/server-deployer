// server.js

const express = require('express');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = 3000;

// Middleware to parse JSON request bodies
app.use(express.json());

// Paths to status and log files
const LOGS_DIR = path.join(__dirname, 'logs');
const STATUS_FILE = path.join(LOGS_DIR, 'deployment_status.txt');
const LOG_FILE = path.join(LOGS_DIR, 'deployment_log.txt');
const LAST_DEPLOYMENT_FILE = path.join(LOGS_DIR, 'last_deployment_status.txt');

// Function to read deployment status
function getDeploymentStatus() {
    try {
        if (fs.existsSync(STATUS_FILE)) {
            const status = fs.readFileSync(STATUS_FILE, 'utf8').trim();
            return status || 'idle';
        } else {
            return 'idle';
        }
    } catch (err) {
        console.error(`Error reading status file: ${err.message}`);
        return 'unknown';
    }
}

// Function to update deployment status
function setDeploymentStatus(status) {
    try {
        fs.writeFileSync(STATUS_FILE, status, 'utf8');
    } catch (err) {
        console.error(`Error writing status file: ${err.message}`);
    }
}

// Function to append logs
function appendDeploymentLog(data) {
    try {
        fs.appendFileSync(LOG_FILE, data, 'utf8');
    } catch (err) {
        console.error(`Error writing log file: ${err.message}`);
    }
}

// Function to read deployment logs
function getDeploymentLogs(lines = 5, full = false) {
    try {
        if (fs.existsSync(LOG_FILE)) {
            const logData = fs.readFileSync(LOG_FILE, 'utf8');
            const logLines = logData.trim().split('\n');
            if (full) {
                return logLines.join('\n');
            } else {
                // Get the last 'lines' lines
                const lastLines = logLines.slice(-lines);
                return lastLines.join('\n');
            }
        } else {
            return '';
        }
    } catch (err) {
        console.error(`Error reading log file: ${err.message}`);
        return '';
    }
}

// Function to set last deployment status (successful or failed)
function setLastDeploymentStatus(status) {
    try {
        fs.writeFileSync(LAST_DEPLOYMENT_FILE, status, 'utf8');
    } catch (err) {
        console.error(`Error writing last deployment status file: ${err.message}`);
    }
}

// Function to get last deployment status
function getLastDeploymentStatus() {
    try {
        if (fs.existsSync(LAST_DEPLOYMENT_FILE)) {
            const status = fs.readFileSync(LAST_DEPLOYMENT_FILE, 'utf8').trim();
            return status || 'unknown';
        } else {
            return 'unknown';
        }
    } catch (err) {
        console.error(`Error reading last deployment status file: ${err.message}`);
        return 'unknown';
    }
}

// Root endpoint with a simple message
app.get('/', (req, res) => {
    res.send('Deployer service available');
});

// Deploy endpoint to trigger deployment
app.post('/deploy', (req, res) => {
    const deploymentStatus = getDeploymentStatus();

    if (deploymentStatus === 'deploying') {
        // Return the current deployment status and logs
        const logs = getDeploymentLogs();
        return res.status(200).json({
            message: 'Deployment is still in progress.',
            status: deploymentStatus,
            logs: logs
        });
    } else {
        // Start a new deployment
        setDeploymentStatus('deploying');
        // Clear previous logs
        fs.writeFileSync(LOG_FILE, '', 'utf8');

        // Send immediate response
        res.status(200).json({
            message: 'Deployment started successfully.',
            status: 'deploying'
        });

        // Command to call the deploy.sh script
        const deployProcess = spawn('bash', [path.join(__dirname, 'scripts/deploy.sh')]);

        // Capture stdout and stderr
        deployProcess.stdout.on('data', (data) => {
            const text = data.toString();
            console.log(`STDOUT: ${text}`);
            appendDeploymentLog(`STDOUT: ${text}`);
        });

        deployProcess.stderr.on('data', (data) => {
            const text = data.toString();
            console.error(`STDERR: ${text}`);
            appendDeploymentLog(`STDERR: ${text}`);
        });

        deployProcess.on('close', (code) => {
            console.log(`Deployment script exited with code ${code}`);
            appendDeploymentLog(`Deployment script exited with code ${code}\n`);

            // Reset deployment status to 'idle'
            setDeploymentStatus('idle');

            if (code === 0) {
                // Deployment succeeded
                setLastDeploymentStatus('successful');
                // Write a success message to the log file
                fs.writeFileSync(LOG_FILE, 'Deployment completed successfully.\n', 'utf8');
            } else {
                // Deployment failed
                setLastDeploymentStatus('failed');
                // Keep the last 5 lines of the log file
                const logData = fs.readFileSync(LOG_FILE, 'utf8');
                const logLines = logData.trim().split('\n');
                const lastLines = logLines.slice(-5);
                fs.writeFileSync(LOG_FILE, lastLines.join('\n') + '\n', 'utf8');
            }
        });

        deployProcess.on('error', (error) => {
            console.error(`Error executing script: ${error.message}`);
            appendDeploymentLog(`Error executing script: ${error.message}\n`);

            // Reset deployment status to 'idle'
            setDeploymentStatus('idle');
            setLastDeploymentStatus('failed');
            // Keep the last 5 lines of the log file
            const logData = fs.readFileSync(LOG_FILE, 'utf8');
            const logLines = logData.trim().split('\n');
            const lastLines = logLines.slice(-5);
            fs.writeFileSync(LOG_FILE, lastLines.join('\n') + '\n', 'utf8');
        });
    }
});

// Status endpoint to check deployment status and logs
app.get('/status', (req, res) => {
    const { full } = req.query;
    const status = getDeploymentStatus();
    const lastDeploymentStatus = getLastDeploymentStatus();

    // Determine whether to return full logs or last 5 lines
    const logs = getDeploymentLogs(5, full === 'true');

    let message = '';

    if (status === 'deploying') {
        message = 'Deployment is in progress.';
    } else if (lastDeploymentStatus === 'successful') {
        message = 'Last deployment was successful.';
    } else if (lastDeploymentStatus === 'failed') {
        message = 'Last deployment failed.';
    } else {
        message = 'No deployment has been run yet.';
    }

    res.status(200).json({
        status: status,
        message: message,
        logs: logs
    });
});

// Start the server
app.listen(PORT, () => {
    console.log(`Server is listening on port ${PORT}`);
});
