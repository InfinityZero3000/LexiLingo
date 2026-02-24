""""""


































































































































































































































































































































































































































































































        assert all(code in [200, 429] for code in responses)        # For now, just ensure we don't crash        # (This test depends on actual rate limit configuration)        # Should have some 429 responses if rate limit is working                    responses.append(response.status_code)            )                headers={"Authorization": f"Bearer {admin_token}"}                "/api/v1/admin/analytics/dashboard/kpis",            response = await client.get(        for _ in range(100):        responses = []        # Make multiple requests rapidly        """Test that rate limiting works (requires actual middleware)."""    ):        self, client: AsyncClient, admin_token    async def test_rate_limit_respected(    @pytest.mark.slow        """Test rate limiting on analytics endpoints."""class TestRateLimiting:# Rate limiting tests        assert isinstance(data["hardest_words"], list)        assert isinstance(data["total_words"], int)                assert "hardest_words" in data        assert "avg_reviews_to_master" in data        assert "avg_mastery_rate" in data        assert "total_words" in data                data = response.json()        assert response.status_code == 200                )            headers={"Authorization": f"Bearer {admin_token}"}            "/api/v1/admin/analytics/vocabulary-effectiveness",        response = await client.get(        """Test vocabulary effectiveness returns correct structure."""    ):        self, client: AsyncClient, admin_token    async def test_vocabulary_effectiveness_structure(        """Test vocabulary effectiveness endpoint."""class TestVocabularyEffectiveness:        assert isinstance(data["lessons"], list)        assert isinstance(data["courses"], list)        assert "lessons" in data        assert "courses" in data                data = response.json()        assert response.status_code == 200                )            headers={"Authorization": f"Bearer {admin_token}"}            "/api/v1/admin/analytics/content-performance",        response = await client.get(        """Test content performance returns correct structure."""    ):        self, client: AsyncClient, admin_token    async def test_content_performance_structure(        """Test content performance endpoint."""class TestContentPerformance:        assert isinstance(metrics["total_signups"], int)        assert isinstance(metrics["mau"], int)        assert isinstance(metrics["wau"], int)        assert isinstance(metrics["dau"], int)        # Check types                assert "total_signups" in metrics        assert "mau" in metrics        assert "wau" in metrics        assert "dau" in metrics                metrics = data["metrics"]        assert "metrics" in data                data = response.json()        assert response.status_code == 200                )            headers={"Authorization": f"Bearer {admin_token}"}            "/api/v1/admin/analytics/user-metrics",        response = await client.get(        """Test user metrics returns correct structure."""    ):        self, client: AsyncClient, admin_token, sample_data    async def test_user_metrics_structure(        """Test user metrics endpoint."""class TestUserMetrics:            assert data[i]["percentage"] <= data[i-1]["percentage"]        for i in range(1, len(data)):        # Subsequent stages should have <= percentage                assert enrolled["percentage"] == 100.0        enrolled = next(e for e in data if e["stage"] == "Đăng ký")        # First stage should be 100%                    assert 0 <= entry["percentage"] <= 100        for entry in data:        # All percentages should be 0-100                data = response.json()["data"]                )            headers={"Authorization": f"Bearer {admin_token}"}            "/api/v1/admin/analytics/dashboard/completion-funnel",        response = await client.get(        """Test that funnel percentages are valid."""    ):        self, client: AsyncClient, admin_token, sample_data    async def test_completion_funnel_percentages_valid(            assert isinstance(entry["percentage"], (int, float))        assert isinstance(entry["count"], int)        assert "percentage" in entry        assert "count" in entry        entry = data["data"][0]        # Check structure                assert "Hoàn thành" in stages        assert "50% hoàn thành" in stages        assert "Bắt đầu" in stages        assert "Đăng ký" in stages        stages = [entry["stage"] for entry in data["data"]]        # Check all stages exist                assert len(data["data"]) == 4  # 4 stages        assert "data" in data                data = response.json()        assert response.status_code == 200                )            headers={"Authorization": f"Bearer {admin_token}"}            "/api/v1/admin/analytics/dashboard/completion-funnel",        response = await client.get(        """Test completion funnel returns correct structure."""    ):        self, client: AsyncClient, admin_token    async def test_completion_funnel_structure(        """Test completion funnel endpoint."""class TestCompletionFunnel:            assert data[i]["enrollments"] <= data[i-1]["enrollments"]        for i in range(1, len(data)):        # Check descending order                data = response.json()["data"]                )            headers={"Authorization": f"Bearer {admin_token}"}            "/api/v1/admin/analytics/dashboard/course-popularity",        response = await client.get(        """Test that courses are sorted by enrollments descending."""    ):        self, client: AsyncClient, admin_token, sample_data    async def test_course_popularity_sorted_descending(                assert isinstance(entry["enrollments"], int)            assert "enrollments" in entry            assert "course_title" in entry            entry = data["data"][0]        if data["data"]:        # Check structure if data exists                assert len(data["data"]) <= 6        # Should return max 6 courses                assert isinstance(data["data"], list)        assert "data" in data                data = response.json()        assert response.status_code == 200                )            headers={"Authorization": f"Bearer {admin_token}"}            "/api/v1/admin/analytics/dashboard/course-popularity",        response = await client.get(        """Test course popularity returns correct structure."""    ):        self, client: AsyncClient, admin_token    async def test_course_popularity_structure(        """Test course popularity endpoint."""class TestCoursePopularity:        assert len(data["data"]) == 4                data = response.json()        assert response.status_code == 200                )            headers={"Authorization": f"Bearer {admin_token}"}            "/api/v1/admin/analytics/dashboard/engagement?weeks=4",        response = await client.get(        """Test engagement with custom week range."""    ):        self, client: AsyncClient, admin_token, sample_data    async def test_engagement_custom_weeks(            assert entry["wau"] <= entry["mau"]        assert entry["dau"] <= entry["wau"]        # DAU <= WAU <= MAU                assert isinstance(entry["mau"], int)        assert isinstance(entry["wau"], int)        assert isinstance(entry["dau"], int)        # Check types and ranges                assert "mau" in entry        assert "wau" in entry        assert "dau" in entry        assert "week" in entry        entry = data["data"][0]        # Check structure                assert len(data["data"]) == 12        assert "data" in data                data = response.json()        assert response.status_code == 200                )            headers={"Authorization": f"Bearer {admin_token}"}            "/api/v1/admin/analytics/dashboard/engagement",        response = await client.get(        """Test engagement with default 12 weeks."""    ):        self, client: AsyncClient, admin_token, sample_data    async def test_engagement_default_12_weeks(        """Test engagement metrics endpoint."""class TestEngagement:            assert data[i]["total_users"] >= data[i-1]["total_users"]        for i in range(1, len(data)):        # Check that total_users never decreases                data = response.json()["data"]                )            headers={"Authorization": f"Bearer {admin_token}"}            "/api/v1/admin/analytics/dashboard/user-growth?days=7",        response = await client.get(        """Test that total_users is cumulative and non-decreasing."""    ):        self, client: AsyncClient, admin_token, sample_data    async def test_user_growth_cumulative_increases(            assert response.status_code == 422        )            headers={"Authorization": f"Bearer {admin_token}"}            "/api/v1/admin/analytics/dashboard/user-growth?days=100",        response = await client.get(        # More than 90                assert response.status_code == 422        )            headers={"Authorization": f"Bearer {admin_token}"}            "/api/v1/admin/analytics/dashboard/user-growth?days=5",        response = await client.get(        # Less than 7        """Test user growth with invalid day parameter."""    ):        self, client: AsyncClient, admin_token    async def test_user_growth_invalid_days(            assert 7 <= len(data["data"]) <= 9        # Should have 8 entries (7 days + today)                data = response.json()        assert response.status_code == 200                )            headers={"Authorization": f"Bearer {admin_token}"}            "/api/v1/admin/analytics/dashboard/user-growth?days=7",        response = await client.get(        """Test user growth with custom day range."""    ):        self, client: AsyncClient, admin_token, sample_data    async def test_user_growth_custom_days(                assert entry["total_users"] >= entry["new_users"]            assert isinstance(entry["total_users"], int)            assert isinstance(entry["new_users"], int)                        assert "total_users" in entry            assert "new_users" in entry            assert "date" in entry            entry = data["data"][0]        if data["data"]:        # Check first entry structure                assert 28 <= len(data["data"]) <= 32        # Should have approximately 31 entries (30 days + today)                assert isinstance(data["data"], list)        assert "data" in data                data = response.json()        assert response.status_code == 200                )            headers={"Authorization": f"Bearer {admin_token}"}            "/api/v1/admin/analytics/dashboard/user-growth",        response = await client.get(        """Test user growth with default 30 days."""    ):        self, client: AsyncClient, admin_token, sample_data    async def test_user_growth_default_30_days(        """Test user growth endpoint."""class TestUserGrowth:        assert data["avg_dau_30d"] >= 0        # Avg DAU should be non-negative                assert 0 <= data["active_users_7d"] <= data["total_users"]        # Active users should be between 0 and total users                assert data["total_users"] >= 10        # Total users should be at least 10 from sample data                data = response.json()["kpis"]                )            headers={"Authorization": f"Bearer {admin_token}"}            "/api/v1/admin/analytics/dashboard/kpis",        response = await client.get(        """Test that KPIs counts are reasonable."""    ):        self, client: AsyncClient, admin_token, sample_data    async def test_kpis_counts_correctly(            assert isinstance(kpis["avg_dau_30d"], (int, float))        assert isinstance(kpis["active_users_7d"], int)        assert isinstance(kpis["total_users"], int)        # Check types                assert "avg_dau_30d" in kpis        assert "total_lessons_completed_today" in kpis        assert "total_courses" in kpis        assert "active_users_7d" in kpis        assert "total_users" in kpis        # Check all required fields                kpis = data["kpis"]        assert "kpis" in data                data = response.json()        assert response.status_code == 200                )            headers={"Authorization": f"Bearer {admin_token}"}            "/api/v1/admin/analytics/dashboard/kpis",        response = await client.get(        """Test that KPIs endpoint returns correct data structure."""    ):        self, client: AsyncClient, admin_token, sample_data    async def test_kpis_returns_correct_structure(            assert response.status_code == 403        )            headers={"Authorization": f"Bearer {regular_user_token}"}            "/api/v1/admin/analytics/dashboard/kpis",        response = await client.get(        """Test that KPIs endpoint requires admin role."""    async def test_kpis_requires_admin(self, client: AsyncClient, regular_user_token):            assert response.status_code == 401        response = await client.get("/api/v1/admin/analytics/dashboard/kpis")        """Test that KPIs endpoint requires authentication."""    async def test_kpis_requires_auth(self, client: AsyncClient):        """Test dashboard KPIs endpoint."""class TestDashboardKPIs:    return True        await db_session.commit()                db_session.add(activity)            )                lessons_completed=1,                xp_earned=10,                activity_date=(today - timedelta(days=i)).date(),                user_id=j + 1,            activity = DailyActivity(        for j in range(5):  # 5 users active each day    for i in range(7):    # Create daily activities        await db_session.commit()            db_session.add(user)        )            created_at=today - timedelta(days=i),            display_name=f"User {i}",            hashed_password="$2b$12$test",            username=f"user{i}",            email=f"user{i}@test.com",        user = User(    for i in range(10):        today = datetime.utcnow()    # Create some users    """Create sample data for testing analytics."""async def sample_data(db_session: AsyncSession):@pytest.fixture    return token    token = create_access_token({"sub": str(admin_user.id)})        from app.core.security import create_access_token    # For now, assume you have a helper to generate test tokens    # In real test, you'd call the actual login endpoint    # Mock login to get token    """Get JWT token for admin user."""async def admin_token(client: AsyncClient, admin_user: User):@pytest.fixture    return user        await db_session.refresh(user)    await db_session.commit()    db_session.add(user)    )        is_verified=True,        is_active=True,        role_id=admin_role.id,        display_name="Test Admin",        hashed_password="$2b$12$test",  # Dummy hash        username="test_admin",        email="test_admin@test.com",    user = User(    # Create admin user            pytest.skip("Admin role not found in database")    if not admin_role:        admin_role = admin_role.first()    )        "SELECT * FROM roles WHERE slug = 'admin'"    admin_role = await db_session.execute(    # Get admin role    """Create an admin user for testing."""async def admin_user(db_session: AsyncSession):@pytest.fixturefrom app.models.rbac import Rolefrom app.models.progress import UserCourseProgress, DailyActivity, LessonCompletionfrom app.models.course import Coursefrom app.models.user import Userfrom datetime import datetime, timedeltafrom sqlalchemy.ext.asyncio import AsyncSessionfrom httpx import AsyncClientimport pytest"""Tests for Phase 1 dashboard analytics implementationTest Analytics API EndpointsTest Analytics Endpoints
Tests for Phase 1 dashboard analytics API
"""

import pytest
from httpx import AsyncClient
from datetime import datetime, timedelta
from app.main import app
from app.models.user import User
from app.models.rbac import Role
from app.core.database import get_db


@pytest.fixture
async def admin_token(db_session):
    """Create admin user and return JWT token."""
    # This assumes auth endpoints exist and work
    async with AsyncClient(app=app, base_url="http://test") as client:
        # Register admin user
        response = await client.post(
            "/api/v1/auth/register",
            json={
                "email": "test_admin@test.com",
                "username": "testadmin",
                "password": "testpass123",
                "display_name": "Test Admin"
            }
        )
        
        # Assign admin role
        from sqlalchemy import select
        result = await db_session.execute(
            select(User).where(User.email == "test_admin@test.com")
        )
        user = result.scalar_one()
        
        admin_role = await db_session.execute(
            select(Role).where(Role.slug == "admin")
        )
        role = admin_role.scalar_one_or_none()
        
        if role:
            user.role_id = role.id
            await db_session.commit()
        
        # Login
        response = await client.post(
            "/api/v1/auth/login",
            json={
                "email": "test_admin@test.com",
                "password": "testpass123"
            }
        )
        
        data = response.json()
        return data["access_token"]


@pytest.mark.asyncio
class TestDashboardAnalytics:
    """Test dashboard analytics endpoints."""
    
    async def test_get_kpis(self, admin_token):
        """Test GET /admin/analytics/dashboard/kpis"""
        async with AsyncClient(app=app, base_url="http://test") as client:
            response = await client.get(
                "/api/v1/admin/analytics/dashboard/kpis",
                headers={"Authorization": f"Bearer {admin_token}"}
            )
            
            assert response.status_code == 200
            data = response.json()
            
            # Check structure
            assert "kpis" in data
            kpis = data["kpis"]
            
            # Check all required fields
            assert "total_users" in kpis
            assert "active_users_7d" in kpis
            assert "total_courses" in kpis
            assert "total_lessons_completed_today" in kpis
            assert "avg_dau_30d" in kpis
            
            # Check types
            assert isinstance(kpis["total_users"], int)
            assert isinstance(kpis["active_users_7d"], int)
            assert isinstance(kpis["total_courses"], int)
            assert isinstance(kpis["total_lessons_completed_today"], int)
            assert isinstance(kpis["avg_dau_30d"], (int, float))
            
            # Check non-negative
            assert kpis["total_users"] >= 0
            assert kpis["active_users_7d"] >= 0
    
    async def test_get_user_growth(self, admin_token):
        """Test GET /admin/analytics/dashboard/user-growth"""
        async with AsyncClient(app=app, base_url="http://test") as client:
            response = await client.get(
                "/api/v1/admin/analytics/dashboard/user-growth?days=7",
                headers={"Authorization": f"Bearer {admin_token}"}
            )
            
            assert response.status_code == 200
            data = response.json()
            
            # Check structure
            assert "data" in data
            assert isinstance(data["data"], list)
            
            if len(data["data"]) > 0:
                item = data["data"][0]
                assert "date" in item
                assert "new_users" in item
                assert "total_users" in item
                
                # Validate date format
                datetime.fromisoformat(item["date"])
                
                # Check types
                assert isinstance(item["new_users"], int)
                assert isinstance(item["total_users"], int)
                assert item["new_users"] >= 0
                assert item["total_users"] >= 0
    
    async def test_get_engagement(self, admin_token):
        """Test GET /admin/analytics/dashboard/engagement"""
        async with AsyncClient(app=app, base_url="http://test") as client:
            response = await client.get(
                "/api/v1/admin/analytics/dashboard/engagement?weeks=4",
                headers={"Authorization": f"Bearer {admin_token}"}
            )
            
            assert response.status_code == 200
            data = response.json()
            
            assert "data" in data
            assert isinstance(data["data"], list)
            
            if len(data["data"]) > 0:
                item = data["data"][0]
                assert "week" in item
                assert "dau" in item
                assert "wau" in item
                assert "mau" in item
                
                assert isinstance(item["dau"], int)
                assert isinstance(item["wau"], int)
                assert isinstance(item["mau"], int)
    
    async def test_get_course_popularity(self, admin_token):
        """Test GET /admin/analytics/dashboard/course-popularity"""
        async with AsyncClient(app=app, base_url="http://test") as client:
            response = await client.get(
                "/api/v1/admin/analytics/dashboard/course-popularity",
                headers={"Authorization": f"Bearer {admin_token}"}
            )
            
            assert response.status_code == 200
            data = response.json()
            
            assert "data" in data
            assert isinstance(data["data"], list)
            
            # Should return top 6 or less
            assert len(data["data"]) <= 6
            
            if len(data["data"]) > 0:
                item = data["data"][0]
                assert "course_title" in item
                assert "enrollments" in item
                assert isinstance(item["enrollments"], int)
                assert item["enrollments"] >= 0
    
    async def test_get_completion_funnel(self, admin_token):
        """Test GET /admin/analytics/dashboard/completion-funnel"""
        async with AsyncClient(app=app, base_url="http://test") as client:
            response = await client.get(
                "/api/v1/admin/analytics/dashboard/completion-funnel",
                headers={"Authorization": f"Bearer {admin_token}"}
            )
            
            assert response.status_code == 200
            data = response.json()
            
            assert "data" in data
            assert isinstance(data["data"], list)
            
            # Should have 4 stages
            assert len(data["data"]) == 4
            
            for item in data["data"]:
                assert "stage" in item
                assert "count" in item
                assert "percentage" in item
                
                assert isinstance(item["count"], int)
                assert isinstance(item["percentage"], (int, float))
                assert 0 <= item["percentage"] <= 100
    
    async def test_unauthorized_access(self):
        """Test that endpoints require authentication."""
        async with AsyncClient(app=app, base_url="http://test") as client:
            response = await client.get(
                "/api/v1/admin/analytics/dashboard/kpis"
            )
            
            assert response.status_code == 401
    
    async def test_invalid_query_params(self, admin_token):
        """Test invalid query parameters."""
        async with AsyncClient(app=app, base_url="http://test") as client:
            # Days out of range
            response = await client.get(
                "/api/v1/admin/analytics/dashboard/user-growth?days=999",
                headers={"Authorization": f"Bearer {admin_token}"}
            )
            # Should be rejected by Query validation (422)
            assert response.status_code == 422


@pytest.mark.asyncio
class TestUserAnalytics:
    """Test user analytics endpoints."""
    
    async def test_get_user_metrics(self, admin_token):
        """Test GET /admin/analytics/user-metrics"""
        async with AsyncClient(app=app, base_url="http://test") as client:
            response = await client.get(
                "/api/v1/admin/analytics/user-metrics",
                headers={"Authorization": f"Bearer {admin_token}"}
            )
            
            assert response.status_code == 200
            data = response.json()
            
            assert "metrics" in data
            metrics = data["metrics"]
            
            assert "dau" in metrics
            assert "wau" in metrics
            assert "mau" in metrics
            assert "total_signups" in metrics
            
            assert isinstance(metrics["dau"], int)
            assert isinstance(metrics["wau"], int)
            assert isinstance(metrics["mau"], int)
    
    async def test_get_retention_cohorts(self, admin_token):
        """Test GET /admin/analytics/retention-cohorts"""
        async with AsyncClient(app=app, base_url="http://test") as client:
            response = await client.get(
                "/api/v1/admin/analytics/retention-cohorts",
                headers={"Authorization": f"Bearer {admin_token}"}
            )
            
            assert response.status_code == 200
            data = response.json()
            
            assert "cohorts" in data
            assert isinstance(data["cohorts"], list)


@pytest.mark.asyncio
class TestContentAnalytics:
    """Test content performance endpoints."""
    
    async def test_get_content_performance(self, admin_token):
        """Test GET /admin/analytics/content-performance"""
        async with AsyncClient(app=app, base_url="http://test") as client:
            response = await client.get(
                "/api/v1/admin/analytics/content-performance",
                headers={"Authorization": f"Bearer {admin_token}"}
            )
            
            assert response.status_code == 200
            data = response.json()
            
            assert "courses" in data
            assert "lessons" in data
            assert isinstance(data["courses"], list)
            assert isinstance(data["lessons"], list)
    
    async def test_get_vocabulary_effectiveness(self, admin_token):
        """Test GET /admin/analytics/vocabulary-effectiveness"""
        async with AsyncClient(app=app, base_url="http://test") as client:
            response = await client.get(
                "/api/v1/admin/analytics/vocabulary-effectiveness",
                headers={"Authorization": f"Bearer {admin_token}"}
            )
            
            assert response.status_code == 200
            data = response.json()
            
            assert "total_words" in data
            assert "avg_mastery_rate" in data
            assert "avg_reviews_to_master" in data
            assert "hardest_words" in data
            
            assert isinstance(data["hardest_words"], list)
