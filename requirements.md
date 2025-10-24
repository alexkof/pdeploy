# Deployment System Requirements

## Main Concept

One universal bash script `pdeploy.sh` that runs locally and fully automates deployment to the server. We will deploy python web and bot applications.

Our product are two scripts 

# pdeploy-init.sh to initialize server

It does following:

* Connects to server using given server address, SSH key, user name
* Target OS: Ubuntu 24+
* Installs all system dependencies needed (build-essential, python dev packages, etc.)
* Installs and configures Cockpit for web-based server management (accessible at https://server:9090)
* Optionally creates admin user with sudo access for Cockpit and disables SSH password authentication
* Installs Python of given version (3.11 by default), if not installed
* Creates venv in `/opt/apps/{APP_NAME}/venv`
* Deploys application files to `/opt/apps/{APP_NAME}`
* Creates systemd service for autostart (runs the specified main file)
* Installs Docker and Traefik with automatic SSL (if app type is web and not installed yet)
* Installs dependencies from `requirements.txt`

# pdeploy.sh to deploy/update app

* Stops systemd service with specified appname
* Uploads python app from current folder to server to `/opt/apps/{APP_NAME}`
* Installs/updates dependencies from `requirements.txt`
* Starts systemd service with specified appname
* Checks it runs successfully and reports result

### 3. Configuration

Settings are stored in `pdeploy.config` file in project root:

```ini
APP_NAME=mybot
APP_TYPE=bot|web
SERVER=111.22.22.11
SSH_USER=root
SSH_KEY=~/.ssh/id_rsa
MAIN_FILE=main.py
WEB_PORT=8080
WEB_DOMAIN=bot.example.com  # optional, required for web apps with SSL
WEB_LETSENCRYPT_EMAIL=admin@example.com  # required for SSL certificates
PYTHON_VERSION=3.11
```

### Other requirements

* Copy files from current directory to server
* Exclude service files typically used in python (venv, __pycache__, .git, .env, *.pyc, .pytest_cache)
* Scripts should install everything needed to run the app on a clean Ubuntu 24+ server
* When init check Python version on server, if it is incompatible - fail with message
* Idempotency: repeated runs are safe
* Support SSH keys for authentication
* Minimal local dependencies (bash and ssh only on local machine)
* After script execution, the application is running, accessible by domain (for web applications), and automatically restarts on failure
* Deployment path convention: `/opt/apps/{APP_NAME}`

### Environment Configuration (.env) Handling

Scripts handle `.env` files with the following logic:

1. If `.env.prod` exists locally → Copy to server as `.env` (overwrites existing)
2. Else if `.env` exists locally → Copy to server as `.env` (overwrites existing)
3. Else if `.env` exists on server → Keep it (don't touch, safe for manual server edits)
4. Else → Fail with error asking to create `.env.prod` or `.env`

**File handling:**
- `.env.prod` is preferred for production deployment
- `.env` is used as fallback if `.env.prod` doesn't exist
- `.env.example` should be committed to git as template
- Both `.env` and `.env.prod` should be in `.gitignore`

### Implementation Approach

* **Server execution:** Using heredoc approach (bash -s with SSH) to keep all logic in 2 main script files
* **Future consideration:** If server-side logic becomes too complex or hard to maintain, consider switching to separate server-side setup scripts (server-init.sh, server-update.sh) that are uploaded and executed remotely

### Usage

First time:

```bash
./pdeploy-init.sh  # reads deploy.config and deploys
./pdeploy.sh  # reads deploy.config and deploys
```

Next time:

```bash
./pdeploy.sh  # reads deploy.config and deploys
```


### Testing


Need to create two test apps in 'tests' folder, one bot and one web app, test server will be provided to test scripts with these apps