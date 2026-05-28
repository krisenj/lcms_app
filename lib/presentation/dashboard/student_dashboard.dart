// lib/presentation/dashboard/student_dashboard.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/router/app_router.dart';
import '../../data/models/user_model.dart';
import '../../providers/theme_provider.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/constants/app_colors.dart';
import '../courses/offline_files_screen.dart';
import '../profile/edit_profile_screen.dart';
import '../profile/unity_avatar_customization_screen.dart';
import '../notifications/notifications_screen.dart';

class StudentDashboard extends ConsumerStatefulWidget {
  const StudentDashboard({super.key});

  @override
  ConsumerState<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends ConsumerState<StudentDashboard>
    with TickerProviderStateMixin {
  // ─── State ───────────────────────────────────────────────
  int _currentIndex = 0;
  final _supabase = Supabase.instance.client;
  UserModel? _currentUser;
  List<Map<String, dynamic>> _enrolledCourses = [];
  List<Map<String, dynamic>> _allCourses = [];
  List<Map<String, dynamic>> _leaderboard = [];
  List<Map<String, dynamic>> _todos = [];
  bool _isLoadingCourses = true;
  bool _isWeekly = true;
  String? _selectedLeaderboardCourseId; // null = All Classes
  final _searchController = TextEditingController();
  String _courseFilter = 'Active';

  // ─── Animation ───────────────────────────────────────────
  late AnimationController _fabController;
  late Animation<double> _fabAnimation;
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  final List<List<Color>> _cardGradients = [
    [const Color(0xFF7B2FBE), const Color(0xFF4A90D9)],
    [const Color(0xFF1565C0), const Color(0xFF00B4D8)],
    [const Color(0xFF6A0572), const Color(0xFF1E90FF)],
    [const Color(0xFF0D47A1), const Color(0xFF00E5FF)],
    [const Color(0xFF4A148C), const Color(0xFF7B1FA2)],
    [const Color(0xFF1A237E), const Color(0xFF283593)],
  ];

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fabAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fabController, curve: Curves.easeOut));
    _fabController.forward();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _loadData();
  }

  @override
  void dispose() {
    _fabController.dispose();
    _glowController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadUser(),
      _loadEnrolledCourses(),
      _loadLeaderboard(),
      _loadTodos(),
    ]);
  }

  Future<void> _loadUser() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final data = await _supabase
          .from('users')
          .select()
          .eq('id', userId)
          .single();
      if (mounted) {
        setState(() {
          _currentUser = UserModel.fromMap(data);
        });
      }
    } catch (e) {
      debugPrint('User load error: $e');
    }
  }

  Future<void> _loadEnrolledCourses() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final data = await _supabase
          .from('enrollments')
          .select('course_id, courses(*)')
          .eq('student_id', userId);
      if (mounted) {
        setState(() {
          _enrolledCourses = List<Map<String, dynamic>>.from(
            data.map((e) => e['courses'] as Map<String, dynamic>),
          );
          _allCourses = _enrolledCourses;
          _isLoadingCourses = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingCourses = false);
    }
  }

  Future<void> _loadLeaderboard({String? courseId}) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      List<String> courseIds;

      if (courseId != null) {
        // ─── Specific class filter selected ───
        courseIds = [courseId];
      } else {
        // ─── All Classes: get all enrolled course IDs ───
        final enrollments = await _supabase
            .from('enrollments')
            .select('course_id')
            .eq('student_id', userId);

        if ((enrollments as List).isEmpty) {
          final selfData = await _supabase
              .from('users')
              .select('id, name, xp, level')
              .eq('id', userId)
              .single();
          if (mounted) {
            setState(
              () => _leaderboard = [Map<String, dynamic>.from(selfData)],
            );
          }
          return;
        }

        courseIds = enrollments.map((e) => e['course_id'] as String).toList();
      }

      // Get all student IDs enrolled in those courses
      final classmateEnrollments = await _supabase
          .from('enrollments')
          .select('student_id')
          .inFilter('course_id', courseIds);

      final classmates = (classmateEnrollments as List)
          .map((e) => e['student_id'] as String)
          .toSet()
          .toList();

      final data = await _supabase
          .from('users')
          .select('id, name, xp, level')
          .inFilter('id', classmates)
          .eq('role', 'student')
          .order('xp', ascending: false)
          .limit(20);

      if (mounted) {
        setState(() => _leaderboard = List<Map<String, dynamic>>.from(data));
      }
    } catch (e) {
      debugPrint('Leaderboard error: $e');
    }
  }

  Future<void> _loadTodos() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final data = await _supabase
          .from('assessments')
          .select('id, title, deadline, course_id, courses(title)')
          .not('deadline', 'is', null)
          .order('deadline', ascending: true)
          .limit(5);
      if (mounted) {
        setState(() {
          _todos = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      debugPrint('Todos error: $e');
    }
  }

  void _showJoinClassDialog() {
    final codeController = TextEditingController();
    bool isJoining = false;
    // Use your system's Dark Blue for text in Light Mode
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    showDialog(
      context: context,
      barrierColor: context.isDark
          ? Colors.black.withValues(alpha: 0.8)
          : Colors.black.withValues(alpha: 0.4),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: context.surfaceColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: context.borderColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primaryDark, AppColors.primary],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.add_circle_outline,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Join a Class',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Ask your instructor for the class code then enter it here.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: textColor.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: codeController,
                    textCapitalization: TextCapitalization.characters,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                    ),
                    decoration: InputDecoration(
                      hintText: 'kfs1fy',
                      hintStyle: TextStyle(
                        color: context.textHint,
                        letterSpacing: 1,
                      ),
                      filled: true,
                      fillColor: context.cardColor,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: context.borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: context.borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: context.cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: context.borderColor),
                            ),
                            child: Center(
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: textColor.withValues(alpha: 0.7),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: isJoining
                              ? null
                              : () async {
                                  final code = codeController.text
                                      .trim()
                                      .toLowerCase();
                                  if (code.isEmpty) return;
                                  setDialogState(() => isJoining = true);
                                  await _joinClass(code);
                                  if (mounted) Navigator.pop(context);
                                },
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppColors.primaryDark,
                                  AppColors.primary,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: isJoining
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Join',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _joinClass(String courseCode) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Find course by code (case insensitive)
      final courseData = await _supabase
          .from('courses')
          .select()
          .ilike('class_code', courseCode)
          .eq('is_published', true)
          .single();

      // Check if already enrolled
      final existing = await _supabase
          .from('enrollments')
          .select()
          .eq('student_id', userId)
          .eq('course_id', courseData['id'])
          .maybeSingle();

      if (existing != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You are already enrolled in this class!'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Enroll student
      await _supabase.from('enrollments').insert({
        'student_id': userId,
        'course_id': courseData['id'],
        'enrolled_at': DateTime.now().toIso8601String(),
      });

      // Refresh data
      await _loadEnrolledCourses();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully joined ${courseData['title']}! 🎉',
              style: const TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('JOIN ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Class not found. Check the code and try again.',
              style: TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  // ─── Leave Class Dialog ─────────────────────────────────
  void _showLeaveClassDialog(Map<String, dynamic> course) {
    showDialog(
      context: context,
      barrierColor: context.isDark
          ? Colors.black.withValues(alpha: 0.8)
          : Colors.black.withValues(alpha: 0.4),
      builder: (context) => Dialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: context.borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.logout, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(
                'Leave Class?',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.isDark
                      ? Colors.white
                      : const Color(0xFF0D1B4B),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Are you sure you want to leave "${course['title']}"? Your progress will be lost.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color:
                      (context.isDark ? Colors.white : const Color(0xFF0D1B4B))
                          .withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: context.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: Center(
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: context.isDark
                                  ? Colors.white
                                  : const Color(0xFF0D1B4B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        Navigator.pop(context);
                        await _leaveClass(course['id']);
                      },
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.red.shade800,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text(
                            'Leave',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _leaveClass(String courseId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      await _supabase
          .from('enrollments')
          .delete()
          .eq('student_id', userId)
          .eq('course_id', courseId);

      // Refresh UI
      setState(() {
        _enrolledCourses.removeWhere((course) => course['id'] == courseId);
      });
      await _loadEnrolledCourses();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Left class successfully')),
        );
      }
    } catch (e) {
      debugPrint('Leave class error: $e');
    }
  }

  Future<void> _openAvatarCustomization() async {
    final updated = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const UnityAvatarCustomizationScreen(),
      ),
    );

    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Avatar updated successfully!'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );

      await _loadUser();
    }
  }

  Future<void> _logout() async {
    await _supabase.auth.signOut();
    if (mounted) context.go(AppRoutes.opening);
  }

  // ─── UTILS ───────────────────────────────────────────────

  String _getLevelTitle(int xp) {
    if (xp >= 2000) return 'Master';
    if (xp >= 1000) return 'Expert';
    if (xp >= 600) return 'Advanced';
    if (xp >= 300) return 'Intermediate';
    if (xp >= 100) return 'Novice';
    return 'Beginner';
  }

  int _getNextLevelXp(int xp) {
    if (xp >= 2000) return 2000;
    if (xp >= 1000) return 2000;
    if (xp >= 600) return 1000;
    if (xp >= 300) return 600;
    if (xp >= 100) return 300;
    return 100;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: Stack(
        children: [
          _buildBackground(),
          if (context.isDark) _buildGlowEffect(MediaQuery.of(context).size),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: IndexedStack(
                    index: _currentIndex,
                    children: [
                      _buildHomePage(),
                      _buildCoursesPage(),
                      _buildLeaderboardPage(),
                      _buildProfilePage(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_currentIndex == 0)
            Positioned(
              bottom: 80,
              right: 20,
              child: ScaleTransition(scale: _fabAnimation, child: _buildFAB()),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBackground() => Container(decoration: context.scaffoldGradient);

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Image.asset(
            'assets/images/app_name.png',
            height: 28,
            fit: BoxFit.contain,
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NotificationsScreen(isInstructor: false),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor),
              ),
              child: Icon(
                Icons.notifications_outlined,
                color: context.isDark ? Colors.white : const Color(0xFF0D1B4B),
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFAB() {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) => GestureDetector(
        onTap: _showJoinClassDialog, // ✅ CHANGED: Now it calls the dialog
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primaryDark, AppColors.primary],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              if (context.isDark)
                BoxShadow(
                  color: AppColors.primary.withValues(
                    alpha: _glowAnimation.value * 0.6,
                  ),
                  blurRadius: 16,
                  spreadRadius: 2,
                )
              else
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    final items = [
      {'icon': Icons.home_outlined, 'activeIcon': Icons.home, 'label': 'Home'},
      {
        'icon': Icons.book_outlined,
        'activeIcon': Icons.book,
        'label': 'Courses',
      },
      {
        'icon': Icons.leaderboard_outlined,
        'activeIcon': Icons.leaderboard,
        'label': 'Ranking',
      },
      {
        'icon': Icons.person_outline,
        'activeIcon': Icons.person,
        'label': 'Profile',
      },
    ];
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: context.cardColor,
        border: Border(
          top: BorderSide(color: context.borderColor.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (index) {
          final isActive = _currentIndex == index;
          return GestureDetector(
            onTap: () => setState(() => _currentIndex = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: isActive
                    ? const LinearGradient(
                        colors: [AppColors.primaryDark, AppColors.primary],
                      )
                    : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isActive
                        ? items[index]['activeIcon'] as IconData
                        : items[index]['icon'] as IconData,
                    color: isActive
                        ? Colors.white
                        : context.isDark
                        ? Colors.white70
                        : const Color(0xFF0D1B4B),
                    size: 22,
                  ),
                  Text(
                    items[index]['label'] as String,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      color: isActive
                          ? Colors.white
                          : context.isDark
                          ? Colors.white70
                          : const Color(0xFF0D1B4B),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // HOME PAGE
  // ════════════════════════════════════════════════════════

  Widget _buildHomePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWelcomeBanner(),
          const SizedBox(height: 24),
          _buildStatsRow(),
          const SizedBox(height: 32),
          _buildSectionHeader(
            'My Classes',
            icon: Icons.auto_stories, // Added proper icon
            onSeeAll: _enrolledCourses.length > 3
                ? () => setState(() => _currentIndex = 1)
                : null,
          ),
          const SizedBox(height: 14),
          if (_isLoadingCourses)
            const Center(child: CircularProgressIndicator())
          else if (_enrolledCourses.isEmpty)
            _buildEmptyClasses()
          else
            Column(
              children: _enrolledCourses
                  .take(3)
                  .map((e) => _buildCourseCard(e, _enrolledCourses.indexOf(e)))
                  .toList(),
            ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildWelcomeBanner() {
    final xp = _currentUser?.xp ?? 0;
    final nextXp = _getNextLevelXp(xp);
    final levelTitle = _getLevelTitle(xp);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7B2FBE), Color(0xFF1E90FF)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Welcome back,',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    Text(
                      _currentUser?.name.split(' ').first ?? 'Student',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              // ─── UPDATED STREAK BADGE ─────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(
                    alpha: 0.15,
                  ), // Semi-transparent white
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_fire_department_rounded, // Proper Fire Icon
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_currentUser?.streak ?? 0} days',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$levelTitle • $xp XP',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              Text(
                '$nextXp XP',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: (xp / nextXp).clamp(0.0, 1.0),
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _buildStatCard(
          Icons.bolt_rounded, // Proper Icon
          '${_currentUser?.xp ?? 0}',
          'Total XP',
          AppColors.gold,
        ),
        const SizedBox(width: 14),
        _buildStatCard(
          Icons.military_tech_rounded, // Proper Icon
          '${_currentUser?.badges.length ?? 0}',
          'Badges',
          AppColors.accent,
        ),
        const SizedBox(width: 14),
        _buildStatCard(
          Icons.auto_stories_rounded, // Proper Icon
          '${_enrolledCourses.length}',
          'Classes',
          AppColors.primary,
        ),
      ],
    );
  }

  Widget _buildStatCard(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.borderColor),
          boxShadow: context.isDark
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Column(
          children: [
            // Icon with a soft background tint
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: textColor.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    String title, {
    IconData? icon,
    VoidCallback? onSeeAll,
  }) {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: AppColors.primary, size: 22), // Proper Icon
              const SizedBox(width: 10),
            ],
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ],
        ),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            child: const Text(
              'See all',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTodoList() {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Column(
      children: _todos.map((todo) {
        final deadline = DateTime.parse(todo['deadline']);
        final daysLeft = deadline.difference(DateTime.now()).inDays;
        final isUrgent = daysLeft <= 1;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isUrgent
                  ? Colors.redAccent.withValues(alpha: 0.5)
                  : context.borderColor,
              width: 1,
            ),
            boxShadow: context.isDark
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isUrgent
                      ? Colors.red.withValues(alpha: 0.1)
                      : AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.assignment_outlined,
                  color: isUrgent ? Colors.redAccent : AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      todo['title'] ?? '',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      todo['courses']?['title'] ?? 'Course',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: textColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isUrgent
                      ? Colors.red.withValues(alpha: 0.1)
                      : AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  daysLeft <= 0
                      ? 'Today!'
                      : daysLeft == 1
                      ? 'Tomorrow'
                      : '$daysLeft days',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isUrgent ? Colors.redAccent : AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCourseCard(Map<String, dynamic> course, int index) {
    final gradient = _cardGradients[index % _cardGradients.length];
    // Use system Dark Blue for Light Mode text
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderColor),
        boxShadow: context.isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        children: [
          // ─── Header Gradient Section ───────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── TOP ROW: Badge and Menu (HIGHER POSITION) ───
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Course Code Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        course['course_code'] ?? 'CPC113',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    // 3-Dot Menu Button (Aligned to the top right)
                    GestureDetector(
                      onTap: () => _showLeaveClassDialog(course),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: const Icon(
                          Icons.more_vert,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ─── TITLE: Below the badge ───
                Text(
                  course['title'] ?? '',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // ─── Body Section ──────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 18,
                      color: textColor.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      course['instructor_name'] ?? 'Instructor',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () {
                    context.push(
                      AppRoutes.courseDetail,
                      extra: {'course': course, 'isInstructor': false},
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: gradient,
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'See class',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyClasses() {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.borderColor),
        boxShadow: context.isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Proper Library Icon instead of emoji
          Icon(
            Icons.library_books_rounded,
            size: 64,
            color: context.isDark
                ? Colors.white24
                : Colors.grey.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 20),
          Text(
            'No classes joined yet',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the + button below to enter your class code and get started!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: textColor.withValues(alpha: 0.6),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCards() {
    return Column(
      children: List.generate(
        2,
        (index) => Container(
          margin: const EdgeInsets.only(bottom: 20),
          height: 180, // Increased height to match actual course card size
          width: double.infinity,
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            children: [
              // Skeleton header
              Expanded(
                flex: 3,
                child: Container(
                  decoration: BoxDecoration(
                    color: context.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                ),
              ),
              // Skeleton body
              Expanded(flex: 2, child: Container()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoursesPage() {
    final titleColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    final filtered = _allCourses.where((c) {
      final matchesSearch =
          _searchController.text.isEmpty ||
          c['title'].toString().toLowerCase().contains(
            _searchController.text.toLowerCase(),
          ) ||
          c['course_code'].toString().toLowerCase().contains(
            _searchController.text.toLowerCase(),
          );

      // Filter logic: match "Active" or "Archived"
      final isArchived = c['is_archived'] == true;
      final matchesFilter = _courseFilter == 'Active'
          ? !isArchived
          : isArchived;

      return matchesSearch && matchesFilter;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'My Courses',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 16),
              // ─── Search Bar ─────────────────
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: titleColor,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Search courses...',
                  hintStyle: TextStyle(color: context.textHint, fontSize: 14),
                  prefixIcon: Icon(
                    Icons.search,
                    color: context.textHint,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: context.cardColor,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // ─── Filter Chips ───────────────
              Row(
                children: ['Active', 'Archived'].map((filter) {
                  final isActive = _courseFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      onTap: () => setState(() => _courseFilter = filter),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: isActive
                              ? const LinearGradient(
                                  colors: [
                                    AppColors.primaryDark,
                                    AppColors.primary,
                                  ],
                                )
                              : null,
                          color: isActive ? null : context.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isActive
                                ? Colors.transparent
                                : context.borderColor,
                          ),
                          boxShadow: [
                            if (!isActive && !context.isDark)
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                          ],
                        ),
                        child: Text(
                          filter,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: isActive
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isActive
                                ? Colors.white
                                : titleColor.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptySearchState()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                  physics: const BouncingScrollPhysics(),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) =>
                      _buildCourseCard(filtered[index], index),
                ),
        ),
      ],
    );
  }

  Widget _buildLeaderboardPage() {
    final currentUserId = _supabase.auth.currentUser?.id;
    // Flexible color: Interstellar Blue in Light Mode, White in Dark Mode
    final themeColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            children: [
              // ─── Header with Proper Icon ───
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.emoji_events_rounded, // Proper Trophy Icon
                    color: AppColors.gold,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Leaderboard',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: themeColor, // Flexible color
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ─── Class Filter Dropdown ────────────────
              if (_enrolledCourses.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: context.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _selectedLeaderboardCourseId != null
                          ? AppColors.primary
                          : context.borderColor,
                      width: _selectedLeaderboardCourseId != null ? 1.5 : 1,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _selectedLeaderboardCourseId,
                      isExpanded: true,
                      dropdownColor: context.surfaceColor,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: themeColor,
                      ),
                      icon: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: _selectedLeaderboardCourseId != null
                            ? AppColors.primary
                            : themeColor.withValues(alpha: 0.5),
                      ),
                      hint: Row(
                        children: [
                          Icon(
                            Icons.groups_rounded,
                            size: 18,
                            color: themeColor.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'All Classes',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              color: themeColor.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Row(
                            children: [
                              Icon(
                                Icons.groups_rounded,
                                size: 18,
                                color: themeColor.withValues(alpha: 0.5),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'All Classes',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: themeColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ..._enrolledCourses.map(
                          (course) => DropdownMenuItem<String?>(
                            value: course['id'] as String,
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    course['title'] ?? '',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 13,
                                      color: themeColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedLeaderboardCourseId = val);
                        _loadLeaderboard(courseId: val);
                      },
                    ),
                  ),
                ),

              const SizedBox(height: 14),

              // Weekly/All-time toggle
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: context.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  children: [
                    _buildTab(
                      'Weekly',
                      _isWeekly,
                      () => setState(() => _isWeekly = true),
                    ),
                    _buildTab(
                      'All-time',
                      !_isWeekly,
                      () => setState(() => _isWeekly = false),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Top 3 podium
        if (_leaderboard.length >= 3)
          _buildPodium(_leaderboard.take(3).toList()),

        const SizedBox(height: 16),

        // ─── Ranking List ───
        Expanded(
          child: _leaderboard.isEmpty
              ? _buildEmptyLeaderboard(themeColor)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  physics: const BouncingScrollPhysics(),
                  itemCount: _leaderboard.length,
                  itemBuilder: (context, index) {
                    final user = _leaderboard[index];
                    final isCurrentUser = user['id'] == currentUserId;
                    final rank = index + 1;

                    final dynamicTextColor = isCurrentUser
                        ? Colors.white
                        : themeColor;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: isCurrentUser
                            ? const LinearGradient(
                                colors: [Color(0xFF1565C0), Color(0xFF1E90FF)],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              )
                            : null,
                        color: isCurrentUser ? null : context.cardColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isCurrentUser
                              ? Colors.transparent
                              : context.borderColor,
                        ),
                      ),
                      child: Row(
                        children: [
                          // ─── Rank Medals instead of Emojis ───
                          SizedBox(
                            width: 32,
                            child: rank <= 3
                                ? Icon(
                                    Icons
                                        .workspace_premium_rounded, // Proper Medal Icon
                                    color: rank == 1
                                        ? AppColors.gold
                                        : rank == 2
                                        ? const Color(0xFFC0C0C0) // Silver
                                        : const Color(0xFFCD7F32), // Bronze
                                    size: 24,
                                  )
                                : Text(
                                    '#$rank',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: dynamicTextColor.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                          ),
                          const SizedBox(width: 12),

                          // Avatar
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: isCurrentUser
                                ? Colors.white24
                                : context.borderColor,
                            child: Text(
                              (user['name'] as String)
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                                color: dynamicTextColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user['name'] ?? '',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: dynamicTextColor,
                                  ),
                                ),
                                Text(
                                  _getLevelTitle(user['xp'] ?? 0),
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    color: isCurrentUser
                                        ? Colors.white70
                                        : context.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // XP
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${user['xp']} XP',
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFFFD700),
                                ),
                              ),
                              if (isCurrentUser)
                                const Text(
                                  'You',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    color: Colors.white70,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // Helper for empty state
  Widget _buildEmptyLeaderboard(Color themeColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.military_tech_outlined,
            size: 64,
            color: themeColor.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'No classmates yet',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: themeColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Join a class to compete with classmates!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPodium(List<Map<String, dynamic>> top3) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 2nd place (Left)
          if (top3.length > 1)
            Expanded(child: _buildPodiumItem(top3[1], 2, 90)),
          const SizedBox(width: 12),

          // 1st place (Center - Tallest)
          if (top3.isNotEmpty)
            Expanded(child: _buildPodiumItem(top3[0], 1, 125)),
          const SizedBox(width: 12),

          // 3rd place (Right)
          if (top3.length > 2)
            Expanded(child: _buildPodiumItem(top3[2], 3, 75)),
        ],
      ),
    );
  }

  Widget _buildPodiumItem(Map<String, dynamic> user, int rank, double height) {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);
    final medalColors = {
      1: const Color(0xFFFFD700), // Gold
      2: const Color(0xFFC0C0C0), // Silver
      3: const Color(0xFFCD7F32), // Bronze
    };
    final emoji = {1: '🥇', 2: '🥈', 3: '🥉'};

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        border: Border.all(
          color: medalColors[rank]!.withValues(alpha: 0.5),
          width: 2,
        ),
        boxShadow: context.isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            emoji[rank]!,
            style: const TextStyle(fontSize: 24),
          ), // ← smaller emoji
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              (user['name'] as String).split(' ').first,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${user['xp']} XP',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              color: medalColors[rank],
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String label, bool isActive, VoidCallback onTap) {
    final inactiveTextColor = context.isDark
        ? Colors.white70
        : const Color(0xFF0D1B4B).withValues(alpha: 0.5);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            gradient: isActive
                ? const LinearGradient(
                    colors: [Color(0xFF1565C0), Color(0xFF1E90FF)],
                  )
                : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                color: isActive ? Colors.white : inactiveTextColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── PROFILE PAGE ─────────────────────────────────────────

  Widget _buildProfilePage() {
    final user = _currentUser;
    final xp = user?.xp ?? 0;
    final nextXp = _getNextLevelXp(xp);
    final levelTitle = _getLevelTitle(xp);

    // Flexible color: Interstellar Blue in Light Mode, White in Dark Mode
    final themeColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          // ─── Profile Header (Stays colorful, text stays white) ───
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7B2FBE), Color(0xFF1E90FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                // ─── EDITABLE AVATAR ───
                GestureDetector(
                  onTap: () async {
                    final updated = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditProfileScreen(user: user!),
                      ),
                    );
                    if (updated == true) _loadUser();
                  },
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 45,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        // Add this line to show the image from Supabase Storage
                        backgroundImage:
                            user?.avatarUrl != null &&
                                user!.avatarUrl!.isNotEmpty
                            ? NetworkImage(user.avatarUrl!)
                            : null,
                        // Only show the letter if there is NO image
                        child:
                            user?.avatarUrl == null || user!.avatarUrl!.isEmpty
                            ? Text(
                                (user?.name ?? 'S')
                                    .substring(0, 1)
                                    .toUpperCase(),
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              )
                            : null,
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF1E90FF),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.edit_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  user?.name ?? 'Student',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  user?.email ?? '',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 20),

                // Role Badge (Proper Icon replaces emoji)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.bolt_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$levelTitle • Level ${user?.level ?? 1}',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$xp XP',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '$nextXp XP',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: (xp / nextXp).clamp(0.0, 1.0),
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ─── Customize Avatar Button ─────────────────────
          GestureDetector(
            onTap: _openAvatarCustomization,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.borderColor),
                boxShadow: context.isDark
                    ? []
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Customize Avatar',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.isDark ? Colors.white : const Color(0xFF0D1B4B),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: context.textSecondary,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ─── Badges Section (Proper Icon replaces emoji) ───
          _buildProfileSection(
            'Badges Earned',
            Icons.military_tech_rounded,
            user?.badges.isEmpty ?? true
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: Text(
                        'No badges yet. Keep learning!',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: themeColor.withValues(alpha: 0.5),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: (user?.badges ?? [])
                          .map(
                            (badge) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF7B2FBE,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(
                                    0xFF7B2FBE,
                                  ).withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                badge,
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF7B2FBE),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
          ),

          const SizedBox(height: 16),

          // ─── Settings Section (Proper Icon replaces emoji) ───
          _buildProfileSection(
            'Settings',
            Icons.settings_rounded,
            Column(
              children: [
                _buildSettingsItem(
                  Icons.dark_mode_outlined,
                  'Dark Mode',
                  trailing: Switch(
                    value: ref.watch(themeProvider) == ThemeMode.dark,
                    onChanged: (_) =>
                        ref.read(themeProvider.notifier).toggleTheme(),
                    activeThumbColor: AppColors.primary,
                  ),
                ),
                _buildSettingsItem(
                  Icons.download_outlined,
                  'Offline Files',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OfflineFilesScreen(),
                    ),
                  ),
                ),
                Divider(color: context.borderColor, height: 1),
                _buildSettingsItem(
                  Icons.logout_rounded,
                  'Logout',
                  color: Colors.redAccent,
                  onTap: _logout,
                ),
              ],
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  // ─── Profile Section Container Helper ───
  Widget _buildProfileSection(String title, IconData icon, Widget content) {
    final themeColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.borderColor),
        boxShadow: context.isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Row(
              children: [
                Icon(icon, color: themeColor, size: 20),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: themeColor,
                  ),
                ),
              ],
            ),
          ),
          content,
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // ─── Settings Row Helper ───
  Widget _buildSettingsItem(
    IconData icon,
    String label, {
    Color? color,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final themeColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);
    final effectiveColor = color ?? themeColor;

    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: effectiveColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: effectiveColor, size: 20),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: effectiveColor,
        ),
      ),
      trailing:
          trailing ??
          Icon(
            Icons.chevron_right,
            color: themeColor.withValues(alpha: 0.3),
            size: 20,
          ),
    );
  }

  Widget _buildGlowEffect(Size size) {
    return Positioned(
      top: -60,
      left: size.width * 0.5 - 120,
      child: AnimatedBuilder(
        animation: _glowAnimation,
        builder: (context, child) => Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(
                  alpha: _glowAnimation.value * 0.5,
                ),
                blurRadius: 100,
                spreadRadius: 30,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper for when search has no results
  Widget _buildEmptySearchState() {
    return Center(
      child: Text(
        'No courses found matching your criteria',
        style: TextStyle(
          fontFamily: 'Poppins',
          color: context.textHint,
          fontSize: 14,
        ),
      ),
    );
  }
}
