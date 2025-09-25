# Blog API

Test API service for NGINX proxy functionality and traffic generation.

## Purpose

Provides backend service for NGINX to proxy requests to, enabling realistic traffic patterns for metrics collection.

## Endpoints

- `GET /health` - Health check
- `GET /posts` - List all blog posts
- `POST /posts` - Create new blog post
- `GET /posts/<id>` - Get specific post
- `PUT /posts/<id>` - Update specific post
- `DELETE /posts/<id>` - Delete specific post
- `GET /posts/search?q=<query>` - Search posts

## Sample Data

Pre-populated with sample blog posts for immediate testing.

## Configuration

- **Port**: 5000 (internal container port)
- **Access**: Via NGINX proxy at `/blog/*` endpoints
- **Storage**: In-memory (data resets on restart)

## Usage

Accessed through NGINX proxy:
```bash
curl http://localhost/blog/health
curl http://localhost/blog/posts
curl -X POST http://localhost/blog/posts -H "Content-Type: application/json" -d '{"title":"Test","content":"Test content"}'
```

Direct access (container networking):
```bash
docker-compose exec nginx curl http://blog-api:5000/health
```