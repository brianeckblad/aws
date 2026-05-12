# awshosting

A Flask application for managing comic book inventory with AWS S3 storage, marketplace exports, and eBay price research.

---

## What It Does

Manage a comic book catalog, upload images to the cloud, export to marketplaces (Whatnot/eBay), research pricing, and generate SKU labels.

- Catalog comics with images and marketplace-ready descriptions
- Cloud storage (AWS S3) with automatic image processing
- Export CSV files for bulk marketplace uploads (Whatnot/eBay)
- eBay price research and market analysis
- SKU label generation for physical inventory
- Trash/recovery system for deleted items
- Multi-user support with individual accounts

---

## Requirements

This application requires AWS cloud services for production use.

| Requirement | Production | Local Development |
|-------------|-----------|-------------------|
| Python 3.8+ | Required | Required |
| AWS account (S3, EC2) | Required | Optional (for S3 access) |
| AWS CLI | Required | Optional |
| Ansible | Required | Not needed |
| eBay Developer account | Optional | Optional |

Estimated monthly cost: $5–10 (S3 + small EC2 instance, free tier eligible).

---

## Local Development

```bash
git clone https://github.com/yourusername/awshosting.git
cd awshosting_1
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

mkdir -p instance/{uploads,item_images,images,exports,snapshots,trash}

python runapp.py
```

Access at `http://localhost:8000`.

For S3 access during local development, create a `.env` file:

```env
AWS_ACCESS_KEY_ID=your_key
AWS_SECRET_ACCESS_KEY=your_secret
S3_BUCKET=your-bucket-name
USERS=username:password
SECRET_KEY=random-secret-here
```

For production, all configuration comes from AWS Secrets Manager. See [Chapter 7: Secret Management](deployment/docs/guides/SECRET_MANAGEMENT.md).

---

## Production Deployment

Start at [Chapter 1: Prerequisites](deployment/docs/guides/PREREQUISITES.md), then follow the chapters in order.

| Method | Time | Guide |
|--------|------|-------|
| Automated | 15–20 min | [Chapter 2: Quick Start](deployment/docs/guides/QUICKSTART.md) |
| Step-by-step | 1–2 hrs | [Chapter 3: Manual Deployment](deployment/docs/guides/MANUAL_DEPLOYMENT.md) |

The [full deployment guide](deployment/docs/README.md) covers 13 chapters: deploy, operate, harden, and decommission.

---

## Architecture

```
Browser
  │
  ▼
Flask (Gunicorn + Nginx)
  ├── Routes ──── URL handlers
  ├── Services ── Business logic (S3, CSV, eBay)
  ├── Models ──── Data structures
  └── Templates ─ HTML/CSS/JS
  │           │
  ▼           ▼
Local        AWS S3
(CSV)       (Images)
```

| Component | Technology |
|-----------|-----------|
| Backend | Flask 3.0+ (Python 3.8+) |
| Storage | CSV files (local), AWS S3 (images), JSON (settings) |
| Image processing | Pillow (WebP thumbnails) |
| Frontend | HTML5, CSS3, JavaScript |
| Deployment | Ansible, Nginx, Gunicorn, Systemd |

No database required. CSV-based storage for portability.

---

## Usage

### Web Interface

| Feature | URL |
|---------|-----|
| Add comic | `/add` |
| Browse inventory | `/browse` |
| Export CSV | `/download` |
| Price lookup | `/price-lookup` |
| Trash | `/trash` |
| Account | `/account` |

### Command Line

```bash
python main.py input.csv          # Batch process CSV
python main.py --s3delete         # Manage S3 images
```

---

## Project Structure

```
awshosting/
├── deployment/
│   ├── playbooks/           Ansible playbooks
│   ├── docs/                Deployment guide (13 chapters)
│   └── group_vars/          Configuration templates
└── requirements.txt         Python dependencies
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Images not uploading to S3 | Check AWS credentials; verify bucket exists and has proper permissions |
| Cannot log in | Verify `USERS` format is `username:password`; check `SECRET_KEY` is set; clear cookies |
| CSV validation errors | Column names are case-sensitive; prices must be >= $1.00 |

See [Chapter 5: Operations — Troubleshooting](deployment/docs/guides/OPERATIONS.md#troubleshooting) for more.

---

## License

MIT License. See [LICENSE](LICENSE).
