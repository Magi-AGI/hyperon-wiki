# AWS EC2 Deployment Guide for Magi-Archive

**Last Updated**: 2025-10-16
**Target Platform**: AWS EC2 + RDS PostgreSQL
**Alternative to**: Railway (simpler but less control)

---

## AWS vs Railway: Key Differences

| Aspect | Railway | AWS EC2 |
|--------|---------|---------|
| **Setup Complexity** | Low (auto-provision) | High (manual configuration) |
| **Cost** | $5-20/month | $10-50+/month (t3.small + RDS) |
| **Control** | Limited | Full server access |
| **Scaling** | Automatic | Manual (or auto-scaling groups) |
| **SSL/HTTPS** | Automatic | Manual (Let's Encrypt) |
| **Database** | Bundled | Separate RDS instance |
| **Monitoring** | Basic included | CloudWatch (separate) |
| **Backups** | Manual snapshots | Automated RDS backups |
| **SSH Access** | Via CLI tool | Direct SSH |

**Recommendation**: Use Railway for initial testing, AWS EC2 for production with multiple collaborators.

---

## Prerequisites

- AWS Account with billing enabled
- Basic familiarity with Linux command line
- SSH client installed locally
- Domain name (optional but recommended for SSL)

### Cost Estimate

**Monthly costs (approximate)**:
- **EC2 t3.small**: $15-17/month (1 year reserved: ~$10/month)
- **RDS db.t3.micro PostgreSQL**: $15-20/month
- **EBS storage (30GB)**: $3/month
- **Data transfer**: $1-5/month (for small wiki)
- **Elastic IP**: Free if attached, $3.60/month if unused
- **Route53 (optional)**: $0.50/month per hosted zone

**Total**: ~$35-45/month (can reduce to ~$28/month with reserved instances)

**Free Tier Eligible** (first 12 months):
- 750 hours/month t3.micro EC2 (use t3.micro instead of t3.small)
- 750 hours/month db.t3.micro RDS
- 30GB EBS storage

With free tier: **$0-5/month** for first year!

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                   AWS Cloud                         │
│                                                     │
│  ┌──────────────┐         ┌──────────────┐        │
│  │   Route53    │────────▶│  Elastic IP  │        │
│  │ (DNS/Domain) │         │  (Static IP) │        │
│  └──────────────┘         └───────┬──────┘        │
│                                    │               │
│  ┌─────────────────────────────────▼─────────────┐ │
│  │           EC2 Instance                        │ │
│  │  ┌──────────────────────────────────────┐    │ │
│  │  │         Nginx (Reverse Proxy)        │    │ │
│  │  │         + Let's Encrypt SSL          │    │ │
│  │  └────────────────┬─────────────────────┘    │ │
│  │  ┌────────────────▼─────────────────────┐    │ │
│  │  │      Puma (Rails Server)             │    │ │
│  │  │      Decko Application               │    │ │
│  │  └────────────────┬─────────────────────┘    │ │
│  └────────────────────┼──────────────────────────┘ │
│                       │                            │
│  ┌────────────────────▼──────────────────────────┐ │
│  │      RDS PostgreSQL Database                  │ │
│  │      (Managed, Auto-backup)                   │ │
│  └───────────────────────────────────────────────┘ │
│                                                     │
│  ┌───────────────────────────────────────────────┐ │
│  │      S3 Bucket (Optional)                     │ │
│  │      For uploaded files/assets                │ │
│  └───────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

---

## Step-by-Step Deployment

### Phase 1: AWS Account Setup

#### 1.1 Create AWS Account
1. Go to https://aws.amazon.com
2. Click "Create an AWS Account"
3. Follow prompts (requires credit card)
4. Enable MFA (Multi-Factor Authentication) for security

#### 1.2 Create IAM User (Best Practice)
```bash
# Don't use root account for daily operations
# Create IAM user with these permissions:
- AmazonEC2FullAccess
- AmazonRDSFullAccess
- AmazonS3FullAccess (if using S3 for uploads)
- AmazonRoute53FullAccess (if using custom domain)
```

1. AWS Console → IAM → Users → Add User
2. Username: `decko-admin`
3. Access type: ✓ Programmatic access, ✓ AWS Management Console access
4. Attach policies: EC2, RDS, S3, Route53
5. Download credentials CSV (save securely!)

---

### Phase 2: RDS Database Setup

#### 2.1 Create RDS PostgreSQL Instance

1. **AWS Console → RDS → Create database**

2. **Configuration**:
   - Engine: **PostgreSQL 15**
   - Template: **Free tier** (first year) or **Production** (multi-AZ)
   - DB instance identifier: `magi-archive-db`
   - Master username: `decko_admin`
   - Master password: `[generate secure password, save to password manager]`

3. **Instance configuration**:
   - Burstable classes: **db.t3.micro** (free tier) or **db.t3.small**
   - Storage: **20 GB** GP3 SSD
   - ✓ Enable storage autoscaling (max 100 GB)

4. **Connectivity**:
   - VPC: Default VPC
   - Public access: **No** (will connect from EC2 only)
   - VPC security group: Create new → `magi-archive-db-sg`

5. **Database authentication**:
   - Password authentication

6. **Additional configuration**:
   - Initial database name: `magi_archive_production`
   - Backup retention: **7 days** (free tier: 1 day)
   - ✓ Enable automatic backups
   - Backup window: **03:00-04:00 UTC** (off-peak)
   - ✓ Enable Enhanced Monitoring (60 seconds)

7. Click **Create database** (takes 5-10 minutes)

#### 2.2 Note Database Credentials

Once created, note these values:
```
Endpoint: magi-archive-db.cz6yeqqqqs2l.us-west-1.rds.amazonaws.com
Port: 5432
Database name: magi_archive_production
Username: decko_admin
Password: [your secure password]
```

---

### Phase 3: EC2 Instance Setup

#### 3.1 Launch EC2 Instance

1. **AWS Console → EC2 → Launch Instance**

2. **Name**: `magi-archive-web`

3. **Application and OS Images (AMI)**:
   - **Ubuntu Server 22.04 LTS** (free tier eligible)

4. **Instance type**:
   - **t3.micro** (free tier) or **t3.small** (recommended)
   - t3.micro: 1 vCPU, 1 GB RAM ($0/month free tier)
   - t3.small: 2 vCPU, 2 GB RAM (~$15/month)

5. **Key pair (login)**:
   - Click "Create new key pair"
   - Name: `magi-archive-key`
   - Type: RSA
   - Format: `.pem` (for SSH)
   - Download and save securely: `~/magi-archive-key.pem`
   - Set permissions: `chmod 400 ~/magi-archive-key.pem`

6. **Network settings**:
   - VPC: Default
   - Auto-assign public IP: **Enable**
   - Firewall (security groups): **Create new**
   - Security group name: `magi-archive-web-sg`
   - Rules:
     - ✓ SSH (port 22) - Source: **My IP** (for security)
     - ✓ HTTP (port 80) - Source: **Anywhere** (0.0.0.0/0)
     - ✓ HTTPS (port 443) - Source: **Anywhere** (0.0.0.0/0)

7. **Configure storage**:
   - 30 GB gp3 SSD (free tier: 30 GB)
   - ✓ Delete on termination

8. **Advanced details** (optional):
   - IAM instance profile: None (or create role for S3 access)

9. Click **Launch instance**

#### 3.2 Allocate Elastic IP (Static IP)

1. **EC2 → Elastic IPs → Allocate Elastic IP address**
2. Click **Allocate**
3. Select the new IP → Actions → **Associate Elastic IP address**
4. Instance: Select `magi-archive-web`
5. Click **Associate**

**Note the Elastic IP**: `54.219.9.17'

#### 3.3 Configure Security Groups

**Allow EC2 to connect to RDS**:

1. **RDS → Databases → magi-archive-db → Connectivity & security**
2. Click on security group: `magi-archive-db-sg`
3. **Inbound rules → Edit inbound rules → Add rule**:
   - Type: **PostgreSQL** (port 5432)
   - Source: **Custom** → Select `magi-archive-web-sg` (EC2 security group)
   - Description: "Allow EC2 web server access"
4. **Save rules**

---

### Phase 4: Server Configuration

#### 4.1 Connect to EC2 Instance

```bash
# From your local machine
# Recommended: add an SSH config so you can use `ssh magi-archive`
# ~/.ssh/config
#   Host magi-archive
#     HostName 54.219.9.17
#     User ubuntu
#     IdentityFile ~/.ssh/magi-archive-key.pem
#     IdentitiesOnly yes

# Connect using alias
ssh magi-archive

# Or connect explicitly if you prefer flags
ssh -i ~/.ssh/magi-archive-key.pem ubuntu@54.219.9.17
```

If connection refused, check:
- Security group allows SSH from your IP
- Using correct key file
- Instance is running (green dot in EC2 console)

#### 4.2 Update System

```bash
# On EC2 instance
sudo apt update && sudo apt upgrade -y

# Install essential tools
sudo apt install -y curl git build-essential libssl-dev \
  libreadline-dev zlib1g-dev libpq-dev nodejs npm
```

#### 4.3 Install Ruby via rbenv

```bash
# Install rbenv
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init -)"' >> ~/.bashrc
source ~/.bashrc

# Install ruby-build
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build

# Install Ruby 3.1 (or version required by Decko)
rbenv install 3.1.4
rbenv global 3.1.4

# Verify
ruby -v  # Should show ruby 3.1.4
gem -v

# Install bundler
gem install bundler
```

#### 4.4 Install PostgreSQL Client

```bash
sudo apt install -y postgresql-client-14

# Test connection to RDS
psql -h magi-archive-db.xxxxxxxxxx.us-east-1.rds.amazonaws.com \
     -U decko_admin -d magi_archive_production

# Enter password when prompted
# Type \q to exit
```

If connection fails:
- Check RDS security group allows EC2 security group
- Verify RDS endpoint hostname
- Check RDS instance is "Available" status

---

### Phase 5: Deploy Decko Application

#### 5.1 Clone or Create Decko App

**Option A: Create New Deck**
```bash
cd /home/ubuntu
gem install decko
decko new magi-archive
cd magi-archive
```

**Option B: Clone from GitLab**
```bash
cd /home/ubuntu
git clone https://gitlab.com/yourusername/magi-archive.git
cd magi-archive
bundle install
```

#### 5.2 Configure Database

Edit `config/database.yml`:

```yaml
production:
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  database: magi_archive_production
  username: decko_admin
  password: <%= ENV['DATABASE_PASSWORD'] %>
  host: magi-archive-db.xxxxxxxxxx.us-east-1.rds.amazonaws.com
  port: 5432
```

#### 5.3 Set Environment Variables

Create `/home/ubuntu/magi-archive/.env.production`:

```bash
# Rails
RAILS_ENV=production
SECRET_KEY_BASE=<generate with: bundle exec rails secret>
RAILS_SERVE_STATIC_FILES=true
RAILS_LOG_TO_STDOUT=true

# Database
DATABASE_PASSWORD=your_rds_password_here

# Application
DECKO_HOST=yourdomain.com  # Or Elastic IP for now
```

**Generate SECRET_KEY_BASE**:
```bash
cd /home/ubuntu/magi-archive
bundle exec rails secret
# Copy output to .env.production
```

#### 5.4 Initialize Database

```bash
cd /home/ubuntu/magi-archive

# Load environment
export $(cat .env.production | xargs)

# Create and seed database
bundle exec rails db:create RAILS_ENV=production
bundle exec decko seed -p  # -p for production

# Run migrations (if any)
bundle exec rails db:migrate RAILS_ENV=production
```

#### 5.5 Precompile Assets

```bash
bundle exec rails assets:precompile RAILS_ENV=production
```

#### 5.6 Test Application

```bash
# Start server (test)
bundle exec puma -C config/puma.rb -e production

# In browser, visit: http://52.x.x.x:3000
# (Use your Elastic IP)
```

**Troubleshooting**:
- Port 3000 blocked? Add to security group temporarily
- 500 error? Check logs: `tail -f log/production.log`
- Database connection error? Verify `.env.production` credentials

Press `Ctrl+C` to stop test server.

---

### Phase 6: Configure Nginx + SSL

#### 6.1 Install Nginx

```bash
sudo apt install -y nginx
```

#### 6.2 Configure Nginx as Reverse Proxy

Create `/etc/nginx/sites-available/magi-archive`:

```nginx
upstream puma {
  server unix:///home/ubuntu/magi-archive/tmp/sockets/puma.sock;
}

server {
  listen 80;
  server_name yourdomain.com www.yourdomain.com;  # Or use Elastic IP

  root /home/ubuntu/magi-archive/public;
  access_log /var/log/nginx/magi-archive-access.log;
  error_log /var/log/nginx/magi-archive-error.log;

  location ^~ /assets/ {
    gzip_static on;
    expires max;
    add_header Cache-Control public;
  }

  try_files $uri/index.html $uri @puma;

  location @puma {
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Host $http_host;
    proxy_redirect off;
    proxy_pass http://puma;
  }

  error_page 500 502 503 504 /500.html;
  client_max_body_size 10M;
  keepalive_timeout 10;
}
```

**For IP-only access** (no domain yet):
```nginx
server_name 52.x.x.x;  # Replace with your Elastic IP
```

#### 6.3 Enable Site

```bash
sudo ln -s /etc/nginx/sites-available/magi-archive /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default  # Remove default site
sudo nginx -t  # Test configuration
sudo systemctl restart nginx
```

#### 6.4 Configure Puma for Unix Socket

Edit `config/puma.rb`:

```ruby
# Puma configuration for production
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

port ENV.fetch("PORT") { 3000 } if ENV['RAILS_ENV'] != 'production'

environment ENV.fetch("RAILS_ENV") { "development" }

if ENV['RAILS_ENV'] == 'production'
  bind 'unix:///home/ubuntu/magi-archive/tmp/sockets/puma.sock'

  pidfile '/home/ubuntu/magi-archive/tmp/pids/puma.pid'
  state_path '/home/ubuntu/magi-archive/tmp/pids/puma.state'

  stdout_redirect '/home/ubuntu/magi-archive/log/puma.stdout.log',
                  '/home/ubuntu/magi-archive/log/puma.stderr.log',
                  true

  workers ENV.fetch("WEB_CONCURRENCY") { 2 }
  preload_app!
end

plugin :tmp_restart
```

Create socket directory:
```bash
mkdir -p /home/ubuntu/magi-archive/tmp/sockets
mkdir -p /home/ubuntu/magi-archive/tmp/pids
```

---

### Phase 7: Systemd Service (Auto-start on Boot)

#### 7.1 Create Systemd Service

Create `/etc/systemd/system/magi-archive.service`:

```ini
[Unit]
Description=Magi Archive Decko Application
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/magi-archive
EnvironmentFile=/home/ubuntu/magi-archive/.env.production
ExecStart=/home/ubuntu/.rbenv/shims/bundle exec puma -C config/puma.rb
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

#### 7.2 Enable and Start Service

```bash
sudo systemctl daemon-reload
sudo systemctl enable magi-archive
sudo systemctl start magi-archive

# Check status
sudo systemctl status magi-archive

# View logs
sudo journalctl -u magi-archive -f
```

#### 7.3 Test Access

Visit in browser:
- **HTTP**: `http://52.x.x.x` (or `http://yourdomain.com`)

Should see Decko welcome page!

---

### Phase 8: SSL Certificate (HTTPS)

**Requires domain name** - if using IP only, skip to Phase 9.

#### 8.1 Point Domain to Elastic IP

**In your domain registrar** (Namecheap, GoDaddy, etc.):
1. Add **A Record**:
   - Host: `@` (root domain)
   - Value: `52.x.x.x` (your Elastic IP)
   - TTL: 300

2. Add **A Record** for www:
   - Host: `www`
   - Value: `52.x.x.x`
   - TTL: 300

Wait 5-60 minutes for DNS propagation.

**Or use Route53** (AWS DNS):
1. **Route53 → Hosted zones → Create hosted zone**
2. Domain name: `yourdomain.com`
3. **Create record**:
   - Record name: blank (root)
   - Type: A
   - Value: `52.x.x.x`
4. Update nameservers at registrar to Route53 nameservers

#### 8.2 Install Certbot (Let's Encrypt)

```bash
sudo apt install -y certbot python3-certbot-nginx
```

#### 8.3 Obtain SSL Certificate

```bash
sudo certbot --nginx -d yourdomain.com -d www.yourdomain.com

# Follow prompts:
# - Email: your@email.com
# - Agree to terms: Yes
# - Share email: No (or yes)
# - Redirect HTTP to HTTPS: Yes (recommended)
```

Certbot will:
- Obtain certificate from Let's Encrypt
- Modify Nginx config to use SSL
- Set up auto-renewal

#### 8.4 Test HTTPS

Visit: `https://yourdomain.com` - should have green padlock!

#### 8.5 Auto-renewal

Certbot installs automatic renewal. Test it:
```bash
sudo certbot renew --dry-run
```

---

### Phase 9: Collaborator Access

#### 9.1 Create User Accounts in Decko

1. **Visit**: `https://yourdomain.com`
2. **Sign up** as administrator (first user)
3. **Create accounts for collaborators**:
   - Click "New User" or similar (Decko-specific UI)
   - Or use Rails console:

```bash
cd /home/ubuntu/magi-archive
bundle exec rails console -e production

# Create user (syntax depends on Decko's auth system)
# Example:
User.create!(
  email: 'collaborator@example.com',
  password: 'temporary_password',
  password_confirmation: 'temporary_password'
)
```

#### 9.2 Share Access Info with Collaborators

Send them:
- **URL**: `https://yourdomain.com`
- **Username/Email**: `their@email.com`
- **Initial Password**: `temporary_password`
- **Instructions**: "Change password on first login"

#### 9.3 Set Up SSH Access for Developers (Optional)

For developers who need server access:

```bash
# On EC2 instance
sudo adduser developer1
sudo usermod -aG sudo developer1  # If they need sudo

# Add their SSH public key
sudo mkdir -p /home/developer1/.ssh
sudo nano /home/developer1/.ssh/authorized_keys
# Paste their public key

sudo chmod 700 /home/developer1/.ssh
sudo chmod 600 /home/developer1/.ssh/authorized_keys
sudo chown -R developer1:developer1 /home/developer1/.ssh
```

Update security group to allow SSH from their IP:
- **EC2 → Security Groups → magi-archive-web-sg**
- **Inbound rules → Edit → Add rule**:
  - Type: SSH
  - Source: `their.ip.address/32`
  - Description: "Developer1 SSH access"

---

### Phase 10: Backups & Maintenance

#### 10.1 RDS Automated Backups

Already configured! RDS automatically backs up database.

**Manual snapshot**:
1. **RDS → Databases → magi-archive-db**
2. **Actions → Take snapshot**
3. Name: `magi-archive-pre-update-2025-10-16`

#### 10.2 Application Code Backups

**Push to GitLab** (best practice):
```bash
cd /home/ubuntu/magi-archive
git add .
git commit -m "Production deployment"
git push origin main
```

#### 10.3 Uploaded Files Backup

If users upload files to `public/uploads`:

**Option A: Sync to S3**
```bash
# Install AWS CLI
sudo apt install -y awscli

# Configure (use IAM user credentials)
aws configure

# Daily backup script
cat > /home/ubuntu/backup-uploads.sh <<'EOF'
#!/bin/bash
aws s3 sync /home/ubuntu/magi-archive/public/uploads \
  s3://magi-archive-backups/uploads/$(date +%Y-%m-%d)
EOF

chmod +x /home/ubuntu/backup-uploads.sh

# Add to crontab
crontab -e
# Add line:
0 3 * * * /home/ubuntu/backup-uploads.sh
```

**Option B: Store uploads in S3 directly**
Configure Decko to use S3 for uploads (recommended for production).

#### 10.4 Monitoring

**CloudWatch Alarms** (optional but recommended):
1. **CloudWatch → Alarms → Create alarm**
2. **EC2 Metrics → CPUUtilization**
3. Threshold: CPU > 80% for 5 minutes
4. Action: Send email notification

**RDS Monitoring**:
- Already enabled (Enhanced Monitoring)
- Check **RDS → magi-archive-db → Monitoring** tab

#### 10.5 System Updates

**Monthly maintenance**:
```bash
sudo apt update && sudo apt upgrade -y
sudo systemctl restart magi-archive
sudo systemctl restart nginx
```

**Check application logs**:
```bash
tail -f /home/ubuntu/magi-archive/log/production.log
sudo journalctl -u magi-archive -n 100
```

---

## Ongoing Operations

### Deploying Updates

```bash
# SSH to server
ssh -i ~/magi-archive-key.pem ubuntu@52.x.x.x

cd /home/ubuntu/magi-archive

# Pull latest code
git pull origin main

# Install dependencies (if Gemfile changed)
bundle install

# Run migrations (if any)
export $(cat .env.production | xargs)
bundle exec rails db:migrate RAILS_ENV=production

# Precompile assets (if changed)
bundle exec rails assets:precompile RAILS_ENV=production

# Restart application
sudo systemctl restart magi-archive

# Check logs
sudo journalctl -u magi-archive -f
```

### Rails Console Access

```bash
cd /home/ubuntu/magi-archive
export $(cat .env.production | xargs)
bundle exec rails console -e production
```

### Database Backup/Restore

**Backup**:
```bash
pg_dump -h magi-archive-db.xxxxxxxxxx.us-east-1.rds.amazonaws.com \
  -U decko_admin -d magi_archive_production \
  > backup-$(date +%Y%m%d).sql
```

**Restore**:
```bash
psql -h magi-archive-db.xxxxxxxxxx.us-east-1.rds.amazonaws.com \
  -U decko_admin -d magi_archive_production \
  < backup-20251016.sql
```

---

## Troubleshooting

### Application won't start
```bash
# Check service status
sudo systemctl status magi-archive

# View logs
sudo journalctl -u magi-archive -n 50

# Common issues:
# - Database connection: Check .env.production credentials
# - Puma socket: Check directory exists and permissions
# - Assets: Run bundle exec rails assets:precompile
```

### Can't connect to database
```bash
# Test from EC2
psql -h [RDS_ENDPOINT] -U decko_admin -d magi_archive_production

# If fails:
# - Check RDS security group allows EC2 security group
# - Check RDS is "Available" in console
# - Verify password in .env.production
```

### 502 Bad Gateway
```bash
# Nginx can't connect to Puma
# Check Puma is running:
ps aux | grep puma

# Check socket exists:
ls -la /home/ubuntu/magi-archive/tmp/sockets/

# Restart both:
sudo systemctl restart magi-archive
sudo systemctl restart nginx
```

### SSL certificate issues
```bash
# Check certificate
sudo certbot certificates

# Renew manually
sudo certbot renew

# Check Nginx config
sudo nginx -t
```

---

## Security Checklist

- [ ] MFA enabled on AWS root account
- [ ] Using IAM user (not root) for operations
- [ ] EC2 security group restricts SSH to known IPs only
- [ ] RDS security group only allows EC2 access (no public access)
- [ ] Strong database password (20+ chars, random)
- [ ] SECRET_KEY_BASE is randomly generated
- [ ] SSL certificate installed (HTTPS only)
- [ ] Regular security updates (`apt upgrade`)
- [ ] RDS automated backups enabled
- [ ] CloudWatch monitoring set up
- [ ] Application logs reviewed regularly
- [ ] Database connection uses SSL (optional: add `sslmode=require` to database.yml)

---

## Cost Optimization Tips

1. **Use Reserved Instances**: Save 30-50% on EC2/RDS with 1-year commitment
2. **Stop instances during inactive hours**: Use Lambda to stop/start on schedule
3. **Use t3.micro free tier**: First 750 hours/month free for 12 months
4. **S3 Intelligent-Tiering**: Auto-move old backups to cheaper storage
5. **CloudWatch log retention**: Set to 7-30 days to avoid accumulation
6. **Delete unused snapshots**: Old RDS snapshots cost money
7. **Elastic IP**: Always attach to instance (unattached IPs cost $0.005/hour)

---

## Next Steps

1. Complete deployment following this guide
2. Test with a few collaborators
3. Set up monitoring and alerts
4. Configure automated backups to S3
5. Document collaborator onboarding process
6. Create runbook for common operations

---

## Additional Resources

- **AWS EC2 Documentation**: https://docs.aws.amazon.com/ec2/
- **AWS RDS Documentation**: https://docs.aws.amazon.com/rds/
- **Decko Documentation**: https://decko.org
- **Let's Encrypt**: https://letsencrypt.org/
- **Nginx Documentation**: https://nginx.org/en/docs/

---

**Estimated Setup Time**: 2-4 hours (first time), 1 hour (with experience)

**Difficulty**: Intermediate (requires Linux and AWS familiarity)
