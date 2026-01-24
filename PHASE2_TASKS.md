# Phase 2 Development Tasks 🚀

**Date Created**: January 25, 2026  
**Phase**: Course Management & Learning Features  
**Duration**: 2 weeks (Week 3-4)  
**Status**: 🟡 Ready to Start

---

## Phase 1 Completion Summary ✅

### Completed (13 commits)
1. ✅ Backend Phase 1-4 models (User, Course, Progress, Gamification)
2. ✅ Backend configuration & middleware
3. ✅ Backend AI client & scripts
4. ✅ Backend documentation (5 docs)
5. ✅ Flutter network layer (envelopes, interceptor)
6. ✅ Flutter auth domain (5 usecases)
7. ✅ Flutter auth data (datasources, models, repository)
8. ✅ Flutter auth presentation (provider)
9. ✅ Flutter core updates (Either pattern)
10. ✅ Flutter dependencies
11. ✅ Flutter tests (32 tests, 100% pass)
12. ✅ Flutter documentation (7 docs)
13. ✅ Chat domain structure

### Phase 1 Stats
- **Backend**: 25 models, 1175+ lines
- **Flutter**: 19 files, 2000+ lines
- **Tests**: 32 unit tests
- **Documentation**: 14 comprehensive docs
- **Commits**: 13 organized by feature

---

## 🎯 Phase 2 Objectives

### Primary Goals
1. **Course Management** - Display courses with Duolingo-style roadmap
2. **Learning Flow** - Lesson navigation and progress tracking
3. **UI/UX** - Implement course screens and widgets
4. **Backend Integration** - Connect Course APIs to frontend

### Success Criteria
- [ ] Users can browse courses (Featured, By Category, Enrolled)
- [ ] Course roadmap displays Units → Lessons hierarchy
- [ ] Lesson progress is tracked and persisted
- [ ] UI matches Duolingo-style design
- [ ] API integration with pagination
- [ ] Unit tests for Course feature (15+ tests)

---

## 📋 Phase 2 Task Breakdown

### Task 2.1: Backend Course API Endpoints (Priority: HIGH) 🔴

**Description**: Create RESTful APIs for course management

#### Sub-tasks
- [ ] 2.1.1: Implement GET /courses endpoint with pagination
  - Query params: page, page_size, category, level, featured
  - Return: PaginatedResponseEnvelope<CourseSchema>
  - Include: course count, units count, enrolled count

- [ ] 2.1.2: Implement GET /courses/{course_id} endpoint
  - Path param: course_id (UUID)
  - Return: ApiResponseEnvelope<CourseDetailSchema>
  - Include: Full course with Units → Lessons hierarchy

- [ ] 2.1.3: Implement GET /courses/{course_id}/units endpoint
  - Path param: course_id
  - Return: ApiResponseEnvelope<List[UnitSchema]>
  - Include: All units with lesson count

- [ ] 2.1.4: Implement POST /courses/{course_id}/enroll endpoint
  - Path param: course_id
  - Body: EnrollmentRequest
  - Return: ApiResponseEnvelope<UserCourseSchema>
  - Action: Create user_course record

- [ ] 2.1.5: Implement GET /users/me/enrolled-courses endpoint
  - Return: ApiResponseEnvelope<List[CourseSchema]>
  - Include: User's enrolled courses with progress

**Estimated Time**: 6 hours  
**Dependencies**: Backend models already exist  
**Files to Create**:
- `backend-service/app/routes/courses.py`
- `backend-service/app/schemas/course.py`
- `backend-service/app/crud/course.py`

---

### Task 2.2: Flutter Course Domain Layer (Priority: HIGH) 🔴

**Description**: Create domain entities and repository interfaces

#### Sub-tasks
- [ ] 2.2.1: Create Course entity
  - File: `lib/features/course/domain/entities/course_entity.dart`
  - Properties: id, title, description, level, category, imageUrl, duration, lessonsCount, isFeatured, rating, enrolledCount, units (nested)

- [ ] 2.2.2: Create Unit and Lesson entities
  - File: `lib/features/course/domain/entities/unit_entity.dart`
  - File: `lib/features/course/domain/entities/lesson_entity.dart`

- [ ] 2.2.3: Create CourseRepository interface
  - File: `lib/features/course/domain/repositories/course_repository.dart`
  - Methods: getAllCourses(), getCourseById(), getEnrolledCourses(), enrollInCourse()
  - Return: Either<Failure, T>

- [ ] 2.2.4: Create Course UseCases
  - `get_courses_usecase.dart`: Fetch paginated courses
  - `get_course_detail_usecase.dart`: Fetch single course
  - `enroll_in_course_usecase.dart`: Enroll user in course
  - `get_enrolled_courses_usecase.dart`: Fetch user's courses

**Estimated Time**: 4 hours  
**Dependencies**: Auth domain pattern  
**Files to Create**: 7 files (3 entities, 1 repository, 4 usecases)

---

### Task 2.3: Flutter Course Data Layer (Priority: HIGH) 🔴

**Description**: Implement data sources and repository

#### Sub-tasks
- [ ] 2.3.1: Create Course models with JSON serialization
  - File: `lib/features/course/data/models/course_model.dart`
  - Extend CourseEntity, implement fromJson/toJson

- [ ] 2.3.2: Create CourseBackendDataSource
  - File: `lib/features/course/data/datasources/course_backend_datasource.dart`
  - Methods: getCourses(), getCourseById(), enrollInCourse(), getEnrolledCourses()
  - Use ApiClient.getEnvelope() and getPaginated()

- [ ] 2.3.3: Implement CourseRepositoryImpl
  - File: `lib/features/course/data/repositories/course_repository_impl.dart`
  - Map API errors to Failures
  - Parse models from envelopes

**Estimated Time**: 5 hours  
**Dependencies**: Auth data layer pattern  
**Files to Create**: 3 files

---

### Task 2.4: Flutter Course Presentation Layer (Priority: HIGH) 🔴

**Description**: Create providers and UI widgets

#### Sub-tasks
- [ ] 2.4.1: Create CourseProvider
  - File: `lib/features/course/presentation/providers/course_provider.dart`
  - State: courses, enrolledCourses, selectedCourse, loading, error
  - Methods: loadCourses(), loadCourseDetail(), enrollInCourse()

- [ ] 2.4.2: Create CourseListScreen
  - File: `lib/features/course/presentation/screens/course_list_screen.dart`
  - Tabs: Featured, All, Enrolled
  - Pagination support
  - Course cards with enroll button

- [ ] 2.4.3: Create CourseDetailScreen
  - File: `lib/features/course/presentation/screens/course_detail_screen.dart`
  - Hero animation from card
  - Course info section
  - Duolingo-style roadmap (Units → Lessons)

- [ ] 2.4.4: Create CourseRoadmapWidget
  - File: `lib/features/course/presentation/widgets/course_roadmap_widget.dart`
  - Visual: Vertical path with nodes
  - Lessons: Circular nodes with icons
  - Progress: Colored nodes (locked/unlocked/completed)

- [ ] 2.4.5: Create CourseCardWidget
  - File: `lib/features/course/presentation/widgets/course_card_widget.dart`
  - Design: Image, title, level badge, progress bar
  - Actions: Tap to detail, enroll button

**Estimated Time**: 10 hours  
**Dependencies**: Auth provider pattern, Material Design  
**Files to Create**: 5 files

---

### Task 2.5: Backend Progress Tracking (Priority: MEDIUM) 🟡

**Description**: API endpoints for lesson progress

#### Sub-tasks
- [ ] 2.5.1: Implement POST /lessons/{lesson_id}/start endpoint
  - Create user_progress record
  - Return: ApiResponseEnvelope<UserProgressSchema>

- [ ] 2.5.2: Implement POST /lessons/{lesson_id}/complete endpoint
  - Update user_progress, user_course
  - Award XP, update streak
  - Return: ApiResponseEnvelope<CompletionResultSchema>

- [ ] 2.5.3: Implement GET /courses/{course_id}/progress endpoint
  - Return user's progress for all lessons in course
  - Calculate completion percentage

**Estimated Time**: 4 hours  
**Dependencies**: Progress models  
**Files to Create**: Update `app/routes/progress.py`

---

### Task 2.6: Flutter Progress Tracking (Priority: MEDIUM) 🟡

**Description**: Frontend progress tracking integration

#### Sub-tasks
- [ ] 2.6.1: Create Progress entities and models
  - `lib/features/progress/domain/entities/lesson_progress_entity.dart`
  - `lib/features/progress/data/models/lesson_progress_model.dart`

- [ ] 2.6.2: Create ProgressRepository and implementation
  - Methods: startLesson(), completeLesson(), getCourseProgress()
  - Return: Either<Failure, T>

- [ ] 2.6.3: Create Progress UseCases
  - `start_lesson_usecase.dart`
  - `complete_lesson_usecase.dart`
  - `get_course_progress_usecase.dart`

- [ ] 2.6.4: Integrate progress into CourseProvider
  - Update roadmap colors based on progress
  - Show completion percentage
  - Lock/unlock lessons

**Estimated Time**: 6 hours  
**Dependencies**: Course feature  
**Files to Create**: 7 files

---

### Task 2.7: Testing Phase 2 (Priority: HIGH) 🔴

**Description**: Unit tests for Course feature

#### Sub-tasks
- [ ] 2.7.1: Test Course models
  - `test/features/course/data/models/course_model_test.dart`
  - JSON parsing, serialization, nested units

- [ ] 2.7.2: Test Course UseCases
  - `test/features/course/domain/usecases/get_courses_usecase_test.dart`
  - Mock repository, test success/failure scenarios

- [ ] 2.7.3: Test Course Provider
  - `test/features/course/presentation/providers/course_provider_test.dart`
  - State changes, loading, errors

- [ ] 2.7.4: Update test scripts
  - Add course tests to test_phase2.sh
  - Target: 15+ tests passing

**Estimated Time**: 5 hours  
**Target**: 15+ tests (Phase 1 + Phase 2 = 47+ tests)  
**Files to Create**: 3+ test files

---

### Task 2.8: Documentation Phase 2 (Priority: LOW) 🟢

**Description**: Update documentation for Phase 2

#### Sub-tasks
- [ ] 2.8.1: Update FLUTTER_DEVELOPMENT_TASKS.md
  - Mark Phase 1 tasks as complete
  - Update Phase 2 progress

- [ ] 2.8.2: Create PHASE2_IMPLEMENTATION_SUMMARY.md
  - Architecture diagrams
  - API contracts
  - Widget tree

- [ ] 2.8.3: Update TEST_RESULTS.md
  - Add Phase 2 test results
  - Update coverage stats

**Estimated Time**: 2 hours  
**Files to Update**: 3 docs

---

## 🗓️ Implementation Timeline

### Week 3 (Days 1-5)
- **Day 1-2**: Task 2.1 (Backend Course APIs)
- **Day 3**: Task 2.2 (Flutter Course Domain)
- **Day 4**: Task 2.3 (Flutter Course Data)
- **Day 5**: Task 2.4.1-2.4.2 (Provider + List Screen)

### Week 4 (Days 6-10)
- **Day 6-7**: Task 2.4.3-2.4.5 (Detail Screen + Widgets)
- **Day 8**: Task 2.5-2.6 (Progress Tracking)
- **Day 9**: Task 2.7 (Testing)
- **Day 10**: Task 2.8 (Documentation) + Buffer

---

## 📊 Phase 2 Metrics

### Development
- **Total Tasks**: 8 major tasks
- **Estimated Time**: 42 hours (~2 weeks)
- **Files to Create**: ~30 files
- **Tests Target**: 15+ unit tests

### Code
- **Backend**: +500 lines (routes, schemas, CRUD)
- **Flutter**: +1500 lines (domain, data, presentation)
- **Tests**: +800 lines

---

## 🔗 Dependencies

### Required from Phase 1
✅ Backend models (Course, Unit, Lesson, UserCourse, UserProgress)  
✅ Flutter network layer (ApiClient, envelopes)  
✅ Flutter auth (for user context)  
✅ Either<Failure, T> pattern  
✅ Test framework (mockito, build_runner)

### External Dependencies
- Backend: SQLAlchemy query optimization
- Flutter: cached_network_image for course images
- Flutter: flutter_svg for roadmap icons

---

## ⚠️ Known Challenges

1. **Duolingo Roadmap UI**: Complex custom painting for path
   - Solution: Use CustomPainter or existing packages (timeline_tile)

2. **Nested JSON Parsing**: Course → Units → Lessons
   - Solution: Recursive fromJson with proper null checks

3. **Pagination State**: Managing offset/page for infinite scroll
   - Solution: Use pagination_view package or custom ScrollController

4. **Progress Calculation**: Real-time updates across widgets
   - Solution: Stream/ChangeNotifier for progress updates

---

## 🎯 Success Metrics

### Phase 2 Complete When:
- [ ] All 8 tasks completed (100%)
- [ ] 15+ unit tests passing
- [ ] Course list, detail, roadmap screens working
- [ ] Backend APIs documented in Swagger
- [ ] Progress tracking functional
- [ ] Code reviewed and merged

### Quality Gates
- ✅ Tests: >90% pass rate
- ✅ Code: No critical errors
- ✅ Performance: List loads in <1s
- ✅ UX: Smooth navigation, no jank
- ✅ Documentation: All APIs documented

---

## 📝 Next Actions

### Immediate (Start Phase 2)
1. Create backend Course routes
2. Setup Flutter Course feature structure
3. Run test_phase1.sh to verify Phase 1 stability

### Before Starting
- [ ] Review Phase 1 code
- [ ] Setup backend dev environment
- [ ] Install Flutter dependencies
- [ ] Read Duolingo UI guidelines

---

**Ready to start Phase 2?** 🚀  
Run: `./scripts/start_phase2.sh` (to be created)
