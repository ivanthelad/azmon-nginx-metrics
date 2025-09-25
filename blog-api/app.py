#!/usr/bin/env python3

import json
import os
import time
import random
from datetime import datetime, timezone
from flask import Flask, request, jsonify
from werkzeug.exceptions import BadRequest, NotFound

app = Flask(__name__)

# In-memory storage for blog posts
posts_db = {}
next_id = 1

# Sample data to pre-populate the blog
SAMPLE_POSTS = [
    {
        "title": "Welcome to the Blog API",
        "content": "This is a sample blog post to demonstrate the JSON API functionality. It includes various endpoints for CRUD operations and search capabilities.",
        "author": "System",
        "tags": ["welcome", "api", "demo"]
    },
    {
        "title": "NGINX Monitoring with Azure",
        "content": "Learn how to monitor NGINX performance using Azure Monitor. This comprehensive guide covers metrics collection, custom dashboards, and alerting strategies for production environments.",
        "author": "DevOps Team",
        "tags": ["nginx", "azure", "monitoring", "devops"]
    },
    {
        "title": "Docker Container Orchestration",
        "content": "Docker containers provide excellent isolation and scalability. This post explores best practices for container orchestration, networking, and security in production deployments.",
        "author": "Infrastructure Team",
        "tags": ["docker", "containers", "orchestration"]
    },
    {
        "title": "Performance Testing Strategies",
        "content": "Effective performance testing requires careful planning and execution. We'll cover load testing, stress testing, and capacity planning for web applications.",
        "author": "QA Team",
        "tags": ["performance", "testing", "optimization"]
    },
    {
        "title": "API Design Best Practices",
        "content": "Building robust APIs requires attention to design principles, error handling, versioning, and documentation. This guide provides practical recommendations for API development.",
        "author": "Development Team",
        "tags": ["api", "design", "development", "best-practices"]
    }
]

def initialize_sample_data():
    """Initialize the blog with sample posts"""
    global next_id
    for i, post_data in enumerate(SAMPLE_POSTS, 1):
        post = create_post_object(
            title=post_data["title"],
            content=post_data["content"],
            author=post_data["author"],
            tags=post_data["tags"]
        )
        post["id"] = i
        post["created_at"] = datetime.now(timezone.utc).isoformat()
        posts_db[i] = post
        next_id = i + 1

def create_post_object(title, content, author="Anonymous", tags=None):
    """Create a new post object with metadata"""
    return {
        "title": title,
        "content": content,
        "author": author,
        "tags": tags or [],
        "created_at": datetime.now(timezone.utc).isoformat(),
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "views": 0,
        "word_count": len(content.split()),
        "reading_time": max(1, len(content.split()) // 200)  # Assume 200 words per minute
    }

def simulate_processing_time():
    """Simulate variable processing time for realistic metrics"""
    # Random delay between 10-100ms to simulate database operations
    time.sleep(random.uniform(0.01, 0.1))

def increment_view_count(post_id):
    """Increment view count for a post"""
    if post_id in posts_db:
        posts_db[post_id]["views"] += 1

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    simulate_processing_time()
    return jsonify({
        "status": "healthy",
        "service": "blog-api",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "total_posts": len(posts_db)
    })

@app.route('/blog/posts', methods=['GET'])
def get_posts():
    """Get all blog posts with optional pagination and filtering"""
    simulate_processing_time()

    # Get query parameters
    page = request.args.get('page', 1, type=int)
    limit = request.args.get('limit', 10, type=int)
    author = request.args.get('author')
    tag = request.args.get('tag')

    # Filter posts
    filtered_posts = list(posts_db.values())

    if author:
        filtered_posts = [p for p in filtered_posts if p['author'].lower() == author.lower()]

    if tag:
        filtered_posts = [p for p in filtered_posts if tag.lower() in [t.lower() for t in p['tags']]]

    # Sort by creation date (newest first)
    filtered_posts.sort(key=lambda x: x['created_at'], reverse=True)

    # Pagination
    start = (page - 1) * limit
    end = start + limit
    paginated_posts = filtered_posts[start:end]

    return jsonify({
        "posts": paginated_posts,
        "pagination": {
            "page": page,
            "limit": limit,
            "total": len(filtered_posts),
            "pages": (len(filtered_posts) + limit - 1) // limit
        },
        "filters": {
            "author": author,
            "tag": tag
        }
    })

@app.route('/blog/posts/<int:post_id>', methods=['GET'])
def get_post(post_id):
    """Get a specific blog post by ID"""
    simulate_processing_time()

    if post_id not in posts_db:
        raise NotFound(f"Post with ID {post_id} not found")

    # Increment view count
    increment_view_count(post_id)

    post = posts_db[post_id].copy()
    post["id"] = post_id

    return jsonify(post)

@app.route('/blog/posts', methods=['POST'])
def create_post():
    """Create a new blog post"""
    simulate_processing_time()

    try:
        data = request.get_json()
        if not data:
            raise BadRequest("Request body must be valid JSON")

        # Validate required fields
        if not data.get('title'):
            raise BadRequest("Title is required")
        if not data.get('content'):
            raise BadRequest("Content is required")

        # Create new post
        global next_id
        post = create_post_object(
            title=data['title'],
            content=data['content'],
            author=data.get('author', 'Anonymous'),
            tags=data.get('tags', [])
        )

        post_id = next_id
        post["id"] = post_id
        posts_db[post_id] = post
        next_id += 1

        return jsonify(post), 201

    except Exception as e:
        if isinstance(e, (BadRequest, NotFound)):
            raise
        raise BadRequest(f"Invalid request: {str(e)}")

@app.route('/blog/posts/<int:post_id>', methods=['PUT'])
def update_post(post_id):
    """Update an existing blog post"""
    simulate_processing_time()

    if post_id not in posts_db:
        raise NotFound(f"Post with ID {post_id} not found")

    try:
        data = request.get_json()
        if not data:
            raise BadRequest("Request body must be valid JSON")

        post = posts_db[post_id]

        # Update fields if provided
        if 'title' in data:
            post['title'] = data['title']
        if 'content' in data:
            post['content'] = data['content']
            post['word_count'] = len(data['content'].split())
            post['reading_time'] = max(1, len(data['content'].split()) // 200)
        if 'author' in data:
            post['author'] = data['author']
        if 'tags' in data:
            post['tags'] = data['tags']

        post['updated_at'] = datetime.now(timezone.utc).isoformat()
        post["id"] = post_id

        return jsonify(post)

    except Exception as e:
        if isinstance(e, (BadRequest, NotFound)):
            raise
        raise BadRequest(f"Invalid request: {str(e)}")

@app.route('/blog/posts/<int:post_id>', methods=['DELETE'])
def delete_post(post_id):
    """Delete a blog post"""
    simulate_processing_time()

    if post_id not in posts_db:
        raise NotFound(f"Post with ID {post_id} not found")

    deleted_post = posts_db.pop(post_id)
    return jsonify({
        "message": f"Post '{deleted_post['title']}' deleted successfully",
        "deleted_post_id": post_id
    })

@app.route('/blog/search', methods=['GET'])
def search_posts():
    """Search blog posts by title or content"""
    simulate_processing_time()

    query = request.args.get('q', '').strip()
    if not query:
        raise BadRequest("Search query parameter 'q' is required")

    # Simple text search in title and content
    matching_posts = []
    query_lower = query.lower()

    for post_id, post in posts_db.items():
        if (query_lower in post['title'].lower() or
            query_lower in post['content'].lower() or
            any(query_lower in tag.lower() for tag in post['tags'])):

            post_copy = post.copy()
            post_copy["id"] = post_id
            matching_posts.append(post_copy)

    # Sort by relevance (title matches first, then content matches)
    def relevance_score(post):
        score = 0
        if query_lower in post['title'].lower():
            score += 10
        if query_lower in post['content'].lower():
            score += 5
        if any(query_lower in tag.lower() for tag in post['tags']):
            score += 3
        return score

    matching_posts.sort(key=relevance_score, reverse=True)

    return jsonify({
        "query": query,
        "results": matching_posts,
        "total": len(matching_posts)
    })

@app.route('/blog/stats', methods=['GET'])
def get_blog_stats():
    """Get blog statistics"""
    simulate_processing_time()

    if not posts_db:
        return jsonify({
            "total_posts": 0,
            "total_views": 0,
            "authors": [],
            "tags": [],
            "average_reading_time": 0
        })

    posts = list(posts_db.values())

    # Calculate statistics
    total_views = sum(post['views'] for post in posts)
    authors = list(set(post['author'] for post in posts))
    all_tags = []
    for post in posts:
        all_tags.extend(post['tags'])
    tag_counts = {}
    for tag in all_tags:
        tag_counts[tag] = tag_counts.get(tag, 0) + 1

    most_viewed = max(posts, key=lambda x: x['views']) if posts else None
    avg_reading_time = sum(post['reading_time'] for post in posts) / len(posts)

    return jsonify({
        "total_posts": len(posts_db),
        "total_views": total_views,
        "total_authors": len(authors),
        "authors": authors,
        "total_tags": len(tag_counts),
        "popular_tags": sorted(tag_counts.items(), key=lambda x: x[1], reverse=True)[:10],
        "average_reading_time": round(avg_reading_time, 1),
        "most_viewed_post": {
            "title": most_viewed['title'],
            "views": most_viewed['views']
        } if most_viewed else None
    })

@app.route('/blog/random', methods=['GET'])
def get_random_post():
    """Get a random blog post"""
    simulate_processing_time()

    if not posts_db:
        raise NotFound("No posts available")

    post_id = random.choice(list(posts_db.keys()))
    increment_view_count(post_id)

    post = posts_db[post_id].copy()
    post["id"] = post_id

    return jsonify(post)

@app.errorhandler(400)
def bad_request(error):
    return jsonify({"error": "Bad Request", "message": str(error.description)}), 400

@app.errorhandler(404)
def not_found(error):
    return jsonify({"error": "Not Found", "message": str(error.description)}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({"error": "Internal Server Error", "message": "Something went wrong"}), 500

if __name__ == '__main__':
    # Initialize with sample data
    initialize_sample_data()

    # Run the Flask app
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)