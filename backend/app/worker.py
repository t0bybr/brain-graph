"""
Celery Worker for Brain Graph Background Tasks
"""
import os
from celery import Celery

# Celery configuration
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")
DATABASE_URL = os.getenv("DATABASE_URL")

# Initialize Celery app
celery_app = Celery(
    "brain_graph",
    broker=REDIS_URL,
    backend=REDIS_URL
)

# Celery configuration
celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,
    task_track_started=True,
    task_time_limit=3600,  # 1 hour
    task_soft_time_limit=3300,  # 55 minutes
    worker_prefetch_multiplier=4,
    worker_max_tasks_per_child=1000,
)

# Task routes (optional)
celery_app.conf.task_routes = {
    "app.tasks.embedding.*": {"queue": "embedding"},
    "app.tasks.graph.*": {"queue": "graph"},
    "app.tasks.decay.*": {"queue": "decay"},
}

# Periodic tasks (Celery Beat schedule)
celery_app.conf.beat_schedule = {
    "compute-decay-scores": {
        "task": "app.tasks.compute_all_decay_scores",
        "schedule": 3600.0,  # Every hour
    },
    "cleanup-expired-scores": {
        "task": "app.tasks.cleanup_expired_scores",
        "schedule": 86400.0,  # Every day
    },
}


# Example tasks (can be moved to app/tasks.py later)
@celery_app.task(name="app.tasks.compute_all_decay_scores")
def compute_all_decay_scores():
    """Compute decay scores for all nodes"""
    # TODO: Implement using database.py connection
    return {"status": "success", "message": "Decay scores computed"}


@celery_app.task(name="app.tasks.cleanup_expired_scores")
def cleanup_expired_scores():
    """Clean up expired scores from database"""
    # TODO: Implement using database.py connection
    return {"status": "success", "message": "Expired scores cleaned up"}


@celery_app.task(name="app.tasks.health_check")
def health_check():
    """Simple health check task"""
    return {"status": "healthy", "worker": "operational"}


# Import tasks to register them (must be after celery_app is defined)
try:
    from app import tasks  # noqa: F401
except ImportError:
    pass  # tasks.py is optional


if __name__ == "__main__":
    celery_app.start()
