// lib/presentation/courses/course_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../data/models/user_model.dart';
import 'file_viewer_screen.dart';
import 'post_detail_screen.dart';
import 'assignment_detail_screen.dart';
import 'class_settings_screen.dart';
import 'dart:async';

class CourseDetailScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> course;
  final bool isInstructor;

  const CourseDetailScreen({
    super.key,
    required this.course,
    required this.isInstructor,
  });

  @override
  ConsumerState<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends ConsumerState<CourseDetailScreen>
    with TickerProviderStateMixin {
  // ─── State ───────────────────────────────────────────────
  int _currentTab = 0;
  final _supabase = Supabase.instance.client;
  UserModel? _currentUser;

  // Stream data
  List<Map<String, dynamic>> _streamPosts = [];
  bool _isLoadingStream = true;

  // Coursework data
  List<Map<String, dynamic>> _topics = [];
  List<Map<String, dynamic>> _posts = [];
  bool _isLoadingCoursework = true;

  // People data
  List<Map<String, dynamic>> _students = [];
  Map<String, dynamic>? _instructor;
  bool _isLoadingPeople = true;

  // Comments state
  final Map<String, bool> _expandedPosts = {};
  final Map<String, List<Map<String, dynamic>>> _comments = {};
  final Map<String, TextEditingController> _commentControllers = {};
  final Map<String, bool> _submittingComment = {};

  // Coursework topic expansion
  final Map<String, bool> _expandedTopics = {};

  // FAB state (instructor coursework)
  bool _fabExpanded = false;

  // ─── Card Gradients ──────────────────────────────────────
  final List<List<Color>> _cardGradients = [
    [const Color(0xFF7B2FBE), const Color(0xFF4A90D9)],
    [const Color(0xFF1565C0), const Color(0xFF00B4D8)],
    [const Color(0xFF6A0572), const Color(0xFF1E90FF)],
    [const Color(0xFF0D47A1), const Color(0xFF00E5FF)],
    [const Color(0xFF4A148C), const Color(0xFF7B1FA2)],
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadStream();
    _loadCoursework();
    _loadPeople();
  }

  @override
  void dispose() {
    _commentControllers.forEach((_, c) => c.dispose());
    super.dispose();
  }

  // ════════════════════════════════════════════════════════
  // DATA LOADING
  // ════════════════════════════════════════════════════════

  Future<void> _loadCurrentUser() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final data = await _supabase
          .from('users')
          .select()
          .eq('id', userId)
          .single();
      if (mounted) setState(() => _currentUser = UserModel.fromMap(data));
    } catch (e) {
      debugPrint('User error: $e');
    }
  }

  Future<void> _loadStream() async {
    try {
      final data = await _supabase
          .from('posts')
          .select('*, users(name)')
          .eq('course_id', widget.course['id'])
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _streamPosts = List<Map<String, dynamic>>.from(data);
          _isLoadingStream = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingStream = false);
    }
  }

  Future<void> _loadCoursework() async {
    try {
      final topicsData = await _supabase
          .from('topics')
          .select()
          .eq('course_id', widget.course['id'])
          .order('order_index');
      final postsData = await _supabase
          .from('posts')
          .select('*, users(name)')
          .eq('course_id', widget.course['id'])
          .neq('type', 'announcement')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          // By using List.from, we ensure the UI sees a brand new list
          // and stops showing the post in its old topic
          _topics = List<Map<String, dynamic>>.from(topicsData);
          _posts = List<Map<String, dynamic>>.from(postsData);
          _isLoadingCoursework = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingCoursework = false);
    }
  }

  Future<void> _loadPeople() async {
    try {
      final instructorData = await _supabase
          .from('users')
          .select()
          .eq('id', widget.course['instructor_id'])
          .single();
      final enrollmentsData = await _supabase
          .from('enrollments')
          .select('users(*)')
          .eq('course_id', widget.course['id']);
      if (mounted) {
        setState(() {
          _instructor = instructorData;
          _students = List<Map<String, dynamic>>.from(
            enrollmentsData.map((e) => e['users'] as Map<String, dynamic>),
          );
          _isLoadingPeople = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingPeople = false);
    }
  }

  Future<void> _loadComments(String postId) async {
    try {
      final data = await _supabase
          .from('comments')
          .select()
          .eq('post_id', postId)
          .order('created_at', ascending: true);
      if (mounted)
        setState(
          () => _comments[postId] = List<Map<String, dynamic>>.from(data),
        );
    } catch (e) {
      debugPrint('Comments error: $e');
    }
  }

  Future<void> _submitComment(String postId) async {
    final controller = _commentControllers[postId];
    if (controller == null || controller.text.trim().isEmpty) return;
    final text = controller.text.trim();
    setState(() => _submittingComment[postId] = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      await _supabase.from('comments').insert({
        'post_id': postId,
        'user_id': userId,
        'user_name': _currentUser?.name ?? 'User',
        'text': text,
        'created_at': DateTime.now().toIso8601String(),
      });
      controller.clear();
      await _loadComments(postId);
    } catch (e) {
      debugPrint('Comment submit error: $e');
    } finally {
      if (mounted) setState(() => _submittingComment[postId] = false);
    }
  }


  Future<void> _createOrUpdateAssessmentForPost({
    required Map<String, dynamic> postData,
    required String title,
    required String type,
  }) async {
    if (type != 'assignment') return;

    final postId = postData['id']?.toString();
    final courseId = postData['course_id'] ?? widget.course['id'];

    if (postId == null || postId.isEmpty || courseId == null) {
      throw Exception('Cannot create assessment: missing post ID or course ID.');
    }

    final existingAssessment = await _supabase
        .from('assessments')
        .select('id')
        .eq('id', postId)
        .maybeSingle();

    if (existingAssessment == null) {
      await _supabase.from('assessments').insert({
        'id': postId,
        'course_id': courseId,
        'title': title,
        'type': 'assignment',
      });
    } else {
      await _supabase
          .from('assessments')
          .update({
            'course_id': courseId,
            'title': title,
            'type': 'assignment',
          })
          .eq('id', postId);
    }
  }

  void _showEditCommentDialog(Map<String, dynamic> comment, String postId) {
    final controller = TextEditingController(text: comment['text']);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.surfaceColor,
        title: Text(
          'Edit Comment',
          style: TextStyle(
            color: context.textPrimary,
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(color: context.textPrimary, fontFamily: 'Poppins'),
          decoration: InputDecoration(
            hintText: 'Type something...',
            hintStyle: TextStyle(color: context.textHint),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _supabase
                  .from('comments')
                  .update({'text': controller.text.trim()})
                  .eq('id', comment['id']);
              Navigator.pop(context);
              _loadComments(postId);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteComment(String commentId, String postId) async {
    try {
      await _supabase.from('comments').delete().eq('id', commentId);
      await _loadComments(postId);
    } catch (e) {
      debugPrint('Delete comment error: $e');
    }
  }

  Future<void> _deletePost(String postId) async {
    try {
      await _supabase.from('posts').delete().eq('id', postId);
      await _loadStream();
      await _loadCoursework();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting post: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _removeStudent(String studentId, String studentName) async {
    try {
      await _supabase
          .from('enrollments')
          .delete()
          .eq('student_id', studentId)
          .eq('course_id', widget.course['id']);
      await _loadPeople();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$studentName has been removed from the class.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Remove student error: $e');
    }
  }

  void _togglePost(String postId) {
    setState(() => _expandedPosts[postId] = !(_expandedPosts[postId] ?? false));
    if (_expandedPosts[postId] == true) {
      _loadComments(postId);
      _commentControllers.putIfAbsent(postId, () => TextEditingController());
    }
  }

  // ════════════════════════════════════════════════════════
  // INSTRUCTOR DIALOGS
  // ════════════════════════════════════════════════════════

  void _showAnnouncementDialog({Map<String, dynamic>? existing}) {
    final titleController = TextEditingController(
      text: existing?['title'] ?? '',
    );
    final instructionsController = TextEditingController(
      text: existing?['instructions'] ?? '',
    );
    bool isPosting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.accent, Color(0xFF9B59B6)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.campaign_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      existing != null
                          ? 'Edit Announcement'
                          : 'Create Announcement',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    20,
                    24,
                    MediaQuery.of(context).viewInsets.bottom + 24,
                  ),
                  child: Column(
                    children: [
                      _buildSheetField(
                        'Announcement Title',
                        'e.g. Class reminder',
                        titleController,
                        Icons.title_outlined,
                      ),
                      const SizedBox(height: 16),
                      _buildSheetField(
                        'Message',
                        'Write your announcement here...',
                        instructionsController,
                        Icons.message_outlined,
                        maxLines: 5,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          onPressed: isPosting
                              ? null
                              : () async {
                                  if (titleController.text.trim().isEmpty)
                                    return;
                                  setSheet(() => isPosting = true);
                                  try {
                                    final userId =
                                        _supabase.auth.currentUser?.id;
                                    if (existing != null) {
                                      await _supabase
                                          .from('posts')
                                          .update({
                                            'title': titleController.text
                                                .trim(),
                                            'instructions':
                                                instructionsController.text
                                                    .trim(),
                                          })
                                          .eq('id', existing['id']);
                                    } else {
                                      await _supabase.from('posts').insert({
                                        'course_id': widget.course['id'],
                                        'instructor_id': userId,
                                        'type': 'announcement',
                                        'title': titleController.text.trim(),
                                        'instructions': instructionsController
                                            .text
                                            .trim(),
                                        'created_at': DateTime.now()
                                            .toIso8601String(),
                                      });
                                    }
                                    if (mounted) {
                                      Navigator.pop(context);
                                      await _loadStream();
                                    }
                                  } catch (e) {
                                    setSheet(() => isPosting = false);
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text('Error: $e'),
                                          backgroundColor: AppColors.error,
                                        ),
                                      );
                                    }
                                  }
                                },
                          child: isPosting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  existing != null
                                      ? 'Save Changes'
                                      : 'Post Announcement',
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreatePostDialog(
    String postType, {
    Map<String, dynamic>? existing,
  }) {
    final titleController = TextEditingController(
      text: existing?['title'] ?? '',
    );
    final instructionsController = TextEditingController(
      text: existing?['instructions'] ?? '',
    );
    final pointsController = TextEditingController(
      text: (existing?['points'] ?? 100).toString(),
    );
    String? selectedTopicId = existing?['topic_id'];

    // ─── Assignment deadline state ───
    DateTime? assignmentDueDate;
    TimeOfDay? assignmentDueTime;
    if (existing?['due_date'] != null) {
      final due = DateTime.parse(existing!['due_date']);
      assignmentDueDate = due;
      assignmentDueTime = TimeOfDay(hour: due.hour, minute: due.minute);
    }

    // ─── Scheduling State (3d_meet) ───
    DateTime? scheduledDate;
    TimeOfDay? scheduledTime;
    int durationMinutes = existing?['duration_minutes'] ?? 60;
    bool isPosting = false;

    if (existing?['scheduled_time'] != null) {
      final dt = DateTime.parse(existing!['scheduled_time']);
      scheduledDate = dt;
      scheduledTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
    }

    // ─── File upload state ───
    String? materialUrl = existing?['material_url'];
    String? materialName = existing?['material_name'];
    String? assessmentUrl = existing?['assessment_url'];
    String? assessmentName = existing?['assessment_name'];
    bool isUploadingMaterial = false;
    bool isUploadingAssessment = false;

    final typeConfig = {
      '3d_meet': {
        'label': '3D Meet Coding',
        'icon': Icons.view_in_ar_outlined,
        'color': const Color(0xFF22C55E),
      },
      'material': {
        'label': 'Lesson Material',
        'icon': Icons.bookmark_outline,
        'color': AppColors.primary,
      },
      'assignment': {
        'label': 'Assignment',
        'icon': Icons.assignment_outlined,
        'color': const Color(0xFFFF6B35),
      },
    };
    final config = typeConfig[postType]!;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Container(
          height: MediaQuery.of(context).size.height * 0.92,
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (config['color'] as Color).withValues(
                          alpha: 0.15,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        config['icon'] as IconData,
                        color: config['color'] as Color,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      existing != null
                          ? 'Edit Post'
                          : config['label'] as String,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    20,
                    24,
                    MediaQuery.of(context).viewInsets.bottom + 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSheetField(
                        'Title',
                        'Enter post title',
                        titleController,
                        Icons.title_outlined,
                      ),
                      const SizedBox(height: 16),

                      _buildSheetField(
                        'Instructions / Description',
                        'What do students need to do?',
                        instructionsController,
                        Icons.description_outlined,
                        maxLines: 4,
                      ),
                      const SizedBox(height: 16),

                      // ─── Lesson Material (Hidden for assignments) ──
                      if (postType != 'assignment') ...[
                        _buildUploadButton(
                          label: materialName ?? 'Attach Lesson Material',
                          icon: materialName != null
                              ? Icons.check_circle
                              : Icons.picture_as_pdf_outlined,
                          color: AppColors.primary,
                          isUploading: isUploadingMaterial,
                          onTap: () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['pdf', 'mp4', 'png', 'jpg'],
                            );
                            if (result == null) return;
                            setSheet(() => isUploadingMaterial = true);
                            try {
                              final file = result.files.first;
                              final bytes = kIsWeb
                                  ? file.bytes!
                                  : await File(file.path!).readAsBytes();
                              final fileName =
                                  '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
                              await _supabase.storage
                                  .from('course-materials')
                                  .uploadBinary(fileName, bytes);
                              final url = _supabase.storage
                                  .from('course-materials')
                                  .getPublicUrl(fileName);
                              setSheet(() {
                                materialUrl = url;
                                materialName = file.name;
                                isUploadingMaterial = false;
                              });
                            } catch (e) {
                              setSheet(() => isUploadingMaterial = false);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ─── Assignment Instruction ──
                      if (postType == '3d_meet' ||
                          postType == 'assignment') ...[
                        _buildUploadButton(
                          label:
                              assessmentName ??
                              'Attach Assessment Instruction (PDF)',
                          icon: assessmentName != null
                              ? Icons.check_circle
                              : Icons.assignment_outlined,
                          color: const Color(0xFFFF6B35),
                          isUploading: isUploadingAssessment,
                          onTap: () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['pdf'],
                            );
                            if (result == null) return;
                            setSheet(() => isUploadingAssessment = true);
                            try {
                              final file = result.files.first;
                              final bytes = kIsWeb
                                  ? file.bytes!
                                  : await File(file.path!).readAsBytes();
                              final fileName =
                                  '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
                              await _supabase.storage
                                  .from('course-assessments')
                                  .uploadBinary(fileName, bytes);
                              final url = _supabase.storage
                                  .from('course-assessments')
                                  .getPublicUrl(fileName);
                              setSheet(() {
                                assessmentUrl = url;
                                assessmentName = file.name;
                                isUploadingAssessment = false;
                              });
                            } catch (e) {
                              setSheet(() => isUploadingAssessment = false);
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (postType == 'assignment') ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6B35).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFFFF6B35).withValues(alpha: 0.25),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.event_available_outlined,
                                    color: Color(0xFFFF6B35),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Assignment Settings',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: pointsController,
                                keyboardType: TextInputType.number,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: context.textPrimary,
                                  fontSize: 14,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Maximum Points',
                                  hintText: 'e.g. 100',
                                  prefixIcon: Icon(
                                    Icons.grade_outlined,
                                    color: context.textHint,
                                    size: 20,
                                  ),
                                  filled: true,
                                  fillColor: context.cardColor,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: context.borderColor),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: context.borderColor),
                                  ),
                                  focusedBorder: const OutlineInputBorder(
                                    borderRadius: BorderRadius.all(Radius.circular(12)),
                                    borderSide: BorderSide(
                                      color: Color(0xFFFF6B35),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildDateTimePicker(
                                context: context,
                                date: assignmentDueDate,
                                time: assignmentDueTime,
                                onDateTap: () async {
                                  final p = await showDatePicker(
                                    context: context,
                                    initialDate: assignmentDueDate ?? DateTime.now(),
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime.now().add(
                                      const Duration(days: 365),
                                    ),
                                  );
                                  if (p != null) {
                                    setSheet(() => assignmentDueDate = p);
                                  }
                                },
                                onTimeTap: () async {
                                  final t = await showTimePicker(
                                    context: context,
                                    initialTime: assignmentDueTime ?? TimeOfDay.now(),
                                  );
                                  if (t != null) {
                                    setSheet(() => assignmentDueTime = t);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      _buildTopicPicker(
                        selectedTopicId,
                        (val) => setSheet(() => selectedTopicId = val),
                      ),
                      const SizedBox(height: 24),

                      // ─── 3D Classroom Schedule (Switch Removed, Always Visible) ───
                      if (postType == '3d_meet') ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF22C55E,
                            ).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(
                                0xFF22C55E,
                              ).withValues(alpha: 0.25),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.calendar_month_outlined,
                                    color: Color(0xFF22C55E),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Classroom Schedule',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _buildDateTimePicker(
                                context: context,
                                date: scheduledDate,
                                time: scheduledTime,
                                onDateTap: () async {
                                  final p = await showDatePicker(
                                    context: context,
                                    initialDate: DateTime.now(),
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime.now().add(
                                      const Duration(days: 365),
                                    ),
                                  );
                                  if (p != null)
                                    setSheet(() => scheduledDate = p);
                                },
                                onTimeTap: () async {
                                  final t = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay.now(),
                                  );
                                  if (t != null)
                                    setSheet(() => scheduledTime = t);
                                },
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Duration',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: context.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [30, 60, 90, 120].map((mins) {
                                  final isSelected = durationMinutes == mins;
                                  // ─── REVISED DURATION LOGIC ───
                                  String label = mins == 90
                                      ? '1.5 hr'
                                      : (mins >= 60
                                            ? '${mins ~/ 60} hr'
                                            : '$mins min');

                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: GestureDetector(
                                      onTap: () => setSheet(
                                        () => durationMinutes = mins,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? const Color(0xFF22C55E)
                                              : context.cardColor,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: isSelected
                                                ? const Color(0xFF22C55E)
                                                : context.borderColor,
                                          ),
                                        ),
                                        child: Text(
                                          label,
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected
                                                ? Colors.white
                                                : context.textSecondary,
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
                        const SizedBox(height: 24),
                      ],

                      // ─── Post Button with Strict Validation ───
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: config['color'] as Color,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          onPressed: isPosting
                              ? null
                              : () async {
                                  String? error;
                                  final title = titleController.text.trim();
                                  final desc = instructionsController.text
                                      .trim();

                                  if (title.isEmpty) {
                                    error = "Post title is required";
                                  } else if (desc.isEmpty)
                                    error =
                                        "Instructions/Description are required";
                                  else if (postType == 'material' &&
                                      materialUrl == null)
                                    error =
                                        "Please attach a Lesson Material file";
                                  else if (postType == 'assignment' &&
                                      assessmentUrl == null)
                                    error =
                                        "Please attach Assignment Instructions (PDF)";
                                  else if (postType == 'assignment' &&
                                      (int.tryParse(pointsController.text.trim()) == null ||
                                          int.parse(pointsController.text.trim()) <= 0))
                                    error = "Please enter valid maximum points";
                                  else if (postType == 'assignment' &&
                                      (assignmentDueDate == null || assignmentDueTime == null))
                                    error = "Please set the assignment deadline date and time";
                                  else if (postType == '3d_meet') {
                                    if (materialUrl == null) {
                                      error =
                                          "Lesson material is required for 3D Meet";
                                    } else if (assessmentUrl == null)
                                      error =
                                          "Assessment instruction is required for 3D Meet";
                                    else if (scheduledDate == null ||
                                        scheduledTime == null)
                                      error =
                                          "Date and Time are required for 3D Meet";
                                  }

                                  if (error != null) {
                                    await showDialog(
                                      context: context,
                                      builder: (dialogContext) => AlertDialog(
                                        backgroundColor: context.surfaceColor,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(18),
                                        ),
                                        title: Text(
                                          'Missing Information',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontWeight: FontWeight.w700,
                                            color: context.textPrimary,
                                          ),
                                        ),
                                        content: Text(
                                          error!,
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            color: context.textSecondary,
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(dialogContext),
                                            child: const Text('OK'),
                                          ),
                                        ],
                                      ),
                                    );
                                    return;
                                  }

                                  setSheet(() => isPosting = true);
                                  try {
                                    final userId =
                                        _supabase.auth.currentUser?.id;
                                    DateTime? finalScheduledTime;
                                    DateTime? finalAssignmentDueDate;
                                    final assignmentPoints =
                                        int.tryParse(pointsController.text.trim()) ?? 100;

                                    if (postType == 'assignment') {
                                      finalAssignmentDueDate = DateTime(
                                        assignmentDueDate!.year,
                                        assignmentDueDate!.month,
                                        assignmentDueDate!.day,
                                        assignmentDueTime!.hour,
                                        assignmentDueTime!.minute,
                                      );
                                    }

                                    if (postType == '3d_meet') {
                                      finalScheduledTime = DateTime(
                                        scheduledDate!.year,
                                        scheduledDate!.month,
                                        scheduledDate!.day,
                                        scheduledTime!.hour,
                                        scheduledTime!.minute,
                                      );
                                    }

                                    // ─── FIX: Check if we are UPDATING or INSERTING ───
                                    if (existing != null) {
                                      // If 'existing' is not null, we UPDATE the current post
                                      await _supabase
                                          .from('posts')
                                          .update({
                                            'title': title,
                                            'instructions': desc,
                                            'topic_id':
                                                selectedTopicId, // This becomes null if "General" is picked
                                            'material_url': materialUrl,
                                            'material_name': materialName,
                                            'assessment_url': assessmentUrl,
                                            'assessment_name': assessmentName,
                                            'scheduled_time': finalScheduledTime?.toUtc().toIso8601String(),
                                            'duration_minutes':
                                                postType == '3d_meet'
                                                ? durationMinutes
                                                : null,
                                            'points': postType == 'assignment'
                                                ? assignmentPoints
                                                : null,
                                            'due_date': postType == 'assignment'
                                                ? finalAssignmentDueDate?.toIso8601String()
                                                : null,
                                          })
                                          .eq('id', existing['id']);

                                      await _createOrUpdateAssessmentForPost(
                                        postData: existing,
                                        title: title,
                                        type: postType,
                                      );
                                    } else {
                                      // If 'existing' is null, we create a NEW post (INSERT)
                                      final postData = await _supabase
                                          .from('posts')
                                          .insert({
                                            'course_id': widget.course['id'],
                                            'instructor_id': userId,
                                            'type': postType,
                                            'title': title,
                                            'instructions': desc,
                                            'topic_id': selectedTopicId,
                                            'material_url': materialUrl,
                                            'material_name': materialName,
                                            'assessment_url': assessmentUrl,
                                            'assessment_name': assessmentName,
                                            'scheduled_time': finalScheduledTime?.toUtc().toIso8601String(),
                                            'duration_minutes':
                                                postType == '3d_meet'
                                                ? durationMinutes
                                                : null,
                                            'points': postType == 'assignment'
                                                ? assignmentPoints
                                                : null,
                                            'due_date': postType == 'assignment'
                                                ? finalAssignmentDueDate?.toIso8601String()
                                                : null,
                                            'created_at': DateTime.now()
                                                .toIso8601String(),
                                          })
                                          .select()
                                          .single();

                                      await _createOrUpdateAssessmentForPost(
                                        postData: Map<String, dynamic>.from(postData),
                                        title: title,
                                        type: postType,
                                      );
                                    }

                                    if (mounted) {
                                      Navigator.pop(context);
                                      // Refresh both tabs
                                      await _loadStream();
                                      await _loadCoursework();
                                    }
                                  } catch (e) {
                                    setSheet(() => isPosting = false);
                                    debugPrint('Error posting: $e');
                                  }
                                },
                          child: isPosting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Post',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateTopicDialog() {
    final titleController = TextEditingController();
    bool isCreating = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => Dialog(
          backgroundColor: context.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: context.borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create Topic',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Topics help organize your coursework into sections.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: context.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: titleController,
                  autofocus: true,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: context.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. Chapter 1, Week 1...',
                    hintStyle: TextStyle(color: context.textHint),
                    filled: true,
                    fillColor: context.cardColor,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
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
                const SizedBox(height: 20),
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
                                color: context.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          minimumSize: const Size(double.infinity, 48),
                          elevation: 0,
                        ),
                        onPressed: isCreating
                            ? null
                            : () async {
                                if (titleController.text.trim().isEmpty) return;
                                setDialog(() => isCreating = true);
                                try {
                                  await _supabase.from('topics').insert({
                                    'course_id': widget.course['id'],
                                    'title': titleController.text.trim(),
                                    'order_index': _topics.length,
                                    'created_at': DateTime.now()
                                        .toIso8601String(),
                                  });
                                  if (mounted) {
                                    Navigator.pop(context);
                                    await _loadCoursework();
                                  }
                                } catch (e) {
                                  setDialog(() => isCreating = false);
                                }
                              },
                        child: isCreating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Create',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w700,
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
      ),
    );
  }

  void _showPostOptions(Map<String, dynamic> post) {
    final type = post['type'] as String;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              post['title'] ?? '',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            _buildOptionTile(
              Icons.edit_outlined,
              'Edit Post',
              AppColors.primary,
              () {
                Navigator.pop(context);
                if (type == 'announcement') {
                  _showAnnouncementDialog(existing: post);
                } else {
                  _showCreatePostDialog(type, existing: post);
                }
              },
            ),
            _buildOptionTile(
              Icons.delete_outline,
              'Delete Post',
              AppColors.error,
              () {
                Navigator.pop(context);
                _showDeletePostConfirmation(post);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeletePostConfirmation(Map<String, dynamic> post) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: context.borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.error,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                'Delete Post?',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This will permanently delete "${post['title']}". This cannot be undone.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: context.textSecondary,
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
                              color: context.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        minimumSize: const Size(double.infinity, 48),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        await _deletePost(post['id']);
                      },
                      child: const Text(
                        'Delete',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
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

  void _showRemoveStudentDialog(Map<String, dynamic> student) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: context.borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.person_remove_outlined,
                color: AppColors.error,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                'Remove Student?',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Remove "${student['name']}" from this class? Their enrollment will be deleted.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: context.textSecondary,
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
                              color: context.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        minimumSize: const Size(double.infinity, 48),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        await _removeStudent(
                          student['id'],
                          student['name'] ?? 'Student',
                        );
                      },
                      child: const Text(
                        'Remove',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
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

  // ════════════════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════════════════

  String _getScheduleStatus(String? scheduledTime) {
  if (scheduledTime == null) return 'none';
  
  try {
    // 1. Parse and convert back to YOUR LOCAL TIME
    final scheduled = DateTime.parse(scheduledTime).toLocal(); 
    
    // 2. Get current device time
    final now = DateTime.now();
    
    final int diff = now.difference(scheduled).inMinutes;

    if (diff < 0) return 'upcoming';
    if (diff >= 0 && diff <= 15) return 'live';
    return 'ended';
  } catch (e) {
    return 'none';
  }
}

String _formatGracePeriodEndTime(String scheduledTime) {
  // ADD .toLocal() HERE
  final dt = DateTime.parse(scheduledTime).toLocal().add(const Duration(minutes: 15));
  
  final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  final min = dt.minute.toString().padLeft(2, '0');
  return '$hour:$min $ampm';
}

  String _formatDate(String dateStr) {
    final date = DateTime.parse(dateStr);
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  String _formatScheduleTime(String? scheduledTime) {
  if (scheduledTime == null) return '';
  
  // ADD .toLocal() HERE
  final dt = DateTime.parse(scheduledTime).toLocal(); 
  
  final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour == 0 ? 12 : dt.hour;
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  final min = dt.minute.toString().padLeft(2, '0');
  return '${months[dt.month - 1]} ${dt.day}, $hour:$min $ampm';
}

  IconData _getPostIcon(String type) {
    switch (type) {
      case '3d_meet':
        return Icons.view_in_ar_outlined;
      case 'material':
        return Icons.bookmark_outline;
      case 'assignment':
        return Icons.assignment_outlined;
      case 'announcement':
        return Icons.campaign_outlined;
      default:
        return Icons.article_outlined;
    }
  }

  Color _getPostColor(String type) {
    switch (type) {
      case '3d_meet':
        return const Color(0xFF22C55E);
      case 'material':
        return AppColors.primary;
      case 'assignment':
        return const Color(0xFFFF6B35);
      case 'announcement':
        return AppColors.accent;
      default:
        return AppColors.primary;
    }
  }

  String _getPostTypeLabel(String type) {
    switch (type) {
      case '3d_meet':
        return '3D Meet';
      case 'material':
        return 'Material';
      case 'assignment':
        return 'Assignment';
      case 'announcement':
        return 'Announcement';
      default:
        return 'Post';
    }
  }

  Widget _buildSheetField(
    String label,
    String hint,
    TextEditingController controller,
    IconData icon, {
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(
        fontFamily: 'Poppins',
        color: context.textPrimary,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          color: context.textSecondary,
        ),
        floatingLabelStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(
          fontFamily: 'Poppins',
          color: context.textHint,
          fontSize: 13,
        ),
        prefixIcon: Icon(icon, color: context.textHint, size: 20),
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
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildAttachmentButton(String label, IconData icon, Color color) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(Icons.attach_file_outlined, color: color, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicPicker(
    String? selectedTopicId,
    ValueChanged<String?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose Topic (optional)',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.borderColor),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: selectedTopicId,
              isExpanded: true,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              borderRadius: BorderRadius.circular(12),
              dropdownColor: context.surfaceColor,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: context.textPrimary,
              ),
              hint: Text(
                'General (no topic)',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: context.textHint,
                  fontSize: 13,
                ),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'General (no topic)',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: context.textHint,
                    ),
                  ),
                ),
                ..._topics.map(
                  (t) => DropdownMenuItem<String?>(
                    value: t['id'],
                    child: Text(
                      '📁 ${t['title']}',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionTile(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildStreamTab(),
      _buildCourseworkTab(),
      _buildPeopleTab(),
      _buildRankingTab(),
    ];

    return Scaffold(
      backgroundColor: context.bgColor,
      body: Stack(
        children: [
          Container(decoration: context.scaffoldGradient),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: pages[_currentTab]),
              ],
            ),
          ),
          // ─── Expanded FAB (Coursework, instructor only) ─
          if (widget.isInstructor && _currentTab == 1) _buildExpandedFAB(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.borderColor),
              ),
              child: Icon(
                Icons.arrow_back,
                color: context.textPrimary,
                size: 20,
              ),
            ),
          ),
          const Spacer(),
          if (widget.isInstructor)
            GestureDetector(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ClassSettingsScreen(course: widget.course),
                  ),
                );
                // Re-fetch course details when returning
                _loadCurrentUser();
                _loadStream();
                _loadCoursework();
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.cardColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.borderColor),
                ),
                child: Icon(
                  Icons.settings_outlined,
                  color: context.textPrimary,
                  size: 20,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCourseCard() {
    final gradientIndex =
        (widget.course['title'] as String? ?? '').length %
        _cardGradients.length;
    final gradient = _cardGradients[gradientIndex];

    return Container(
      width: double
          .infinity, // Ensures it matches the width of containers below it
      margin: const EdgeInsets.only(bottom: 12), // Only vertical spacing
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(
          20,
        ), // Standardized with announcement bar
        boxShadow: [
          BoxShadow(
            color: gradient[0].withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.course['course_code'] ?? '',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.course['title'] ?? '',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline,
                      color: Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.course['instructor_name'] ?? 'Instructor',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: Colors.white70,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.people_outline,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${widget.course['enrolled_count'] ?? 0}',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    final items = [
      {
        'icon': Icons.forum_outlined,
        'activeIcon': Icons.forum,
        'label': 'Stream',
      },
      {
        'icon': Icons.assignment_outlined,
        'activeIcon': Icons.assignment,
        'label': 'Coursework',
      },
      {
        'icon': Icons.people_outline,
        'activeIcon': Icons.people,
        'label': 'People',
      },
      {
        'icon': Icons.leaderboard_outlined,
        'activeIcon': Icons.leaderboard,
        'label': 'Ranking',
      },
    ];

    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: context.cardColor,
        border: Border(
          top: BorderSide(
            color: context.borderColor.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (index) {
          final isActive = _currentTab == index;
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                _currentTab = index;
                _fabExpanded = false;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                        ? Colors.white54
                        : const Color(0xFF0D1B4B).withValues(alpha: 0.4),
                    size: 22,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items[index]['label'] as String,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                      color: isActive
                          ? Colors.white
                          : context.isDark
                          ? Colors.white54
                          : const Color(0xFF0D1B4B).withValues(alpha: 0.4),
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

  // ─── Expanded FAB ─────────────────────────────────────────
  Widget _buildExpandedFAB() {
    final fabItems = [
      {
        'label': '3D Meet Coding',
        'icon': Icons.view_in_ar_outlined,
        'color': const Color(0xFF22C55E),
        'type': '3d_meet',
      },
      {
        'label': 'Lesson Material',
        'icon': Icons.bookmark_outline,
        'color': AppColors.primary,
        'type': 'material',
      },
      {
        'label': 'Assignment',
        'icon': Icons.assignment_outlined,
        'color': const Color(0xFFFF6B35),
        'type': 'assignment',
      },
      {
        'label': 'Topic',
        'icon': Icons.folder_outlined,
        'color': AppColors.accent,
        'type': 'topic',
      },
    ];

    return Positioned(
      bottom: 80,
      right: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mini FAB options
          if (_fabExpanded) ...[
            ...fabItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () {
                    setState(() => _fabExpanded = false);
                    if (item['type'] == 'topic') {
                      _showCreateTopicDialog();
                    } else {
                      _showCreatePostDialog(item['type'] as String);
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Label
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: context.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.borderColor),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          item['label'] as String,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Icon button
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: item['color'] as Color,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: (item['color'] as Color).withValues(
                                alpha: 0.35,
                              ),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(
                          item['icon'] as IconData,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // Main FAB
          GestureDetector(
            onTap: () => setState(() => _fabExpanded = !_fabExpanded),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primaryDark, AppColors.primary],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                _fabExpanded ? Icons.close : Icons.add,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // STREAM TAB
  // ════════════════════════════════════════════════════════
  Widget _buildStreamTab() {
    if (_isLoadingStream) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadStream,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        children: [
          // Course card in Stream only
          _buildCourseCard(),

          // Instructor: Create Announcement button
          if (widget.isInstructor) ...[
            GestureDetector(
              onTap: () => _showAnnouncementDialog(),
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: context.cardColor,
                  borderRadius: BorderRadius.circular(
                    16,
                  ), // Increased radius for modern look
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                      child: Text(
                        (_currentUser?.name ?? 'I')
                            .substring(0, 1)
                            .toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Announce something to your class...',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: context.textHint,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.campaign_outlined,
                      color: AppColors.accent,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          ],

          // ─── Posts Section ───
          if (_streamPosts.isEmpty)
            _buildEmptyState(
              Icons.campaign_rounded, // Proper Icon instead of Emoji
              'No posts yet',
              widget.isInstructor
                  ? 'Post an announcement to get started!'
                  : 'Your instructor hasn\'t posted anything yet.',
            )
          else
            ..._streamPosts.map((post) => _buildStreamCard(post)),
        ],
      ),
    );
  }

  Widget _buildStreamCard(Map<String, dynamic> post) {
    final postId = post['id'] as String;
    final isExpanded = _expandedPosts[postId] ?? false;
    final type = post['type'] as String;
    final postColor = _getPostColor(type);
    final postIcon = _getPostIcon(type);
    final comments = _comments[postId] ?? [];
    final isAnnouncement = type == 'announcement';
    final instructorName =
        post['users']?['name'] ??
        widget.course['instructor_name'] ??
        'Instructor';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
        boxShadow: context.isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => post['type'] == 'assignment'
                    ? AssignmentDetailScreen(
                        post: post,
                        course: widget.course,
                        isInstructor: widget.isInstructor,
                      )
                    : PostDetailScreen(
                        post: post,
                        course: widget.course,
                        isInstructor: widget.isInstructor,
                      ),
              ),
            ).then((_) => _loadStream()),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: postColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: isAnnouncement
                            ? Center(
                                child: Text(
                                  instructorName.substring(0, 1).toUpperCase(),
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: postColor,
                                  ),
                                ),
                              )
                            : Icon(postIcon, color: postColor, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isAnnouncement
                                  ? instructorName
                                  : post['title'] ?? '',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: context.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  _formatDate(post['created_at']),
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    color: context.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: postColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _getPostTypeLabel(type),
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: postColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // ─── 3 dot menu (instructor only) ──────
                      if (widget.isInstructor)
                        GestureDetector(
                          onTap: () => _showPostOptions(post),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.more_vert,
                              color: context.textSecondary,
                              size: 20,
                            ),
                          ),
                        )
                      else
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: context.textSecondary,
                          size: 20,
                        ),
                    ],
                  ),
                  if (post['instructions'] != null && !isExpanded) ...[
                    const SizedBox(height: 8),
                    Text(
                      post['instructions'],
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: context.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),

          if (isExpanded) ...[
            Divider(color: context.borderColor, height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (post['instructions'] != null) ...[
                    Text(
                      post['instructions'],
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: context.textPrimary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (post['material_url'] != null)
                    _buildFileAttachment(
                      post['material_name'] ?? 'Lesson Material',
                      Icons.picture_as_pdf_outlined,
                      AppColors.primary,
                      post['material_url'],
                    ),
                  if (post['assessment_url'] != null)
                    _buildFileAttachment(
                      post['assessment_name'] ?? 'Assessment Instructions',
                      Icons.assignment_outlined,
                      const Color(0xFFFF6B35),
                      post['assessment_url'],
                    ),
                  if (post['scheduled_time'] != null) ...[
                    const SizedBox(height: 12),
                    _buildJoin3DButton(post['scheduled_time']),
                  ],
                  const SizedBox(height: 16),
                  _buildCommentsSection(postId, comments),
                ],
              ),
            ),
          ],

          if (!isExpanded) ...[
            Divider(color: context.borderColor, height: 1),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => post['type'] == 'assignment'
                      ? AssignmentDetailScreen(
                          post: post,
                          course: widget.course,
                          isInstructor: widget.isInstructor,
                        )
                      : PostDetailScreen(
                          post: post,
                          course: widget.course,
                          isInstructor: widget.isInstructor,
                        ),
                ),
              ).then((_) => _loadStream()),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: AppColors.primary.withValues(
                        alpha: 0.15,
                      ),
                      child: Text(
                        (_currentUser?.name ?? 'U')
                            .substring(0, 1)
                            .toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Add class comment...',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: context.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFileAttachment(
    String name,
    IconData icon,
    Color color, [
    String? url,
  ]) {
    return GestureDetector(
      onTap: url != null
          ? () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    FileViewerScreen(url: url, fileName: name),
              ),
            )
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (url != null) ...[
              Icon(Icons.visibility_outlined, color: color, size: 15),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: color, size: 15),
            ] else
              Icon(Icons.attach_file_outlined, color: color, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildJoin3DButton(String scheduledTime) {
  final status = _getScheduleStatus(scheduledTime);
  final isLive = status == 'live';
  final isUpcoming = status == 'upcoming';
  final Color btnColor = isLive ? const Color(0xFF22C55E) : Colors.grey;

  return GestureDetector(
    onTap: isLive ? () { /* Your Join Logic */ } : null,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: isLive ? btnColor : btnColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isLive ? Icons.videogame_asset : Icons.videogame_asset_outlined, color: Colors.white),
          const SizedBox(width: 10),
          Column(
            children: [
              Text(isLive ? 'Join 3D Classroom' : isUpcoming ? 'Scheduled' : 'Ended',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
        ],
      ),
    ),
  );
}


  Widget _buildCommentsSection(String postId, List<Map<String, dynamic>> comments) {
    // 1. Use the Map-based state instead of singular variables
    final controller = _commentControllers[postId] ?? (_commentControllers[postId] = TextEditingController());
    final isSubmitting = _submittingComment[postId] ?? false;
    final currentUserId = _supabase.auth.currentUser?.id;
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Header ───
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text('Class Comments',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                fontWeight: FontWeight.bold, color: textColor)),
        ),
        Divider(color: context.borderColor, height: 1),

        // ─── Comment List ───
        if (comments.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: Text('No comments yet.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: context.textHint)),
            ),
          ),

        ...comments.map((comment) {
          final isOwn = comment['user_id'] == currentUserId;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: Text(
                    (comment['user_name'] as String).substring(0, 1).toUpperCase(),
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                        fontWeight: FontWeight.bold, color: AppColors.primary)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: context.isDark ? context.bgColor : Colors.grey.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.borderColor.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(comment['user_name'] ?? '',
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                                  fontWeight: FontWeight.bold, color: textColor)),
                            const Spacer(),
                            Text(_formatDate(comment['created_at']),
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: context.textHint)),
                            
                            if (isOwn || widget.isInstructor)
                              PopupMenuButton<String>(
                                icon: Icon(Icons.more_vert, size: 14, color: context.textHint),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                                onSelected: (value) {
                                  // 2. Added the second required argument: postId
                                  if (value == 'delete') _deleteComment(comment['id'], postId); 
                                  if (value == 'edit') _showEditCommentDialog(comment, postId); 
                                },
                                itemBuilder: (context) => [
                                  if (isOwn && widget.isInstructor)
                                    const PopupMenuItem(value: 'edit', child: Text('Edit', style: TextStyle(fontSize: 12))),
                                  const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(fontSize: 12, color: Colors.red))),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(comment['text'] ?? '',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: textColor, height: 1.3)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),

        // ─── Input Field ───
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                // 3. Use _currentUser?.name instead of _currentUserName
                child: Text((_currentUser?.name ?? 'U').substring(0, 1).toUpperCase(),
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Add class comment...',
                    hintStyle: TextStyle(fontSize: 13, color: context.textHint),
                    filled: true, 
                    fillColor: context.isDark ? context.bgColor : Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: context.borderColor)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: context.borderColor)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                    suffixIcon: IconButton(
                      // 4. Pass the postId to the submission function
                      onPressed: () => _submitComment(postId), 
                      icon: isSubmitting
                          ? const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
                          : const Icon(Icons.send_rounded, color: AppColors.primary, size: 18),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════
  // COURSEWORK TAB
  // ════════════════════════════════════════════════════════
  Widget _buildCourseworkTab() {
    if (_isLoadingCoursework) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    final generalPosts = _posts.where((p) => p['topic_id'] == null).toList();
    final topicMap = <String, List<Map<String, dynamic>>>{};
    for (final topic in _topics) {
      topicMap[topic['id']] = _posts
          .where((p) => p['topic_id'] == topic['id'])
          .toList();
    }

    // ─── Empty State (Replaced emoji with Icon) ───
    if (_posts.isEmpty && _topics.isEmpty) {
      return _buildEmptyState(
        Icons.library_books_rounded, // Proper Icon
        'No coursework yet',
        widget.isInstructor
            ? 'Tap the + button to create your first post'
            : 'Your instructor hasn\'t posted any coursework yet.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        if (generalPosts.isNotEmpty) ...[
          _buildTopicSection(
            'General',
            'general',
            generalPosts,
            key: const ValueKey('topic_general'), // Added Key
          ),
          const SizedBox(height: 12),
        ],
        ..._topics
            .map(
              (topic) => Column(
                key: ValueKey('topic_col_${topic['id']}'), // Added Key here
                children: [
                  _buildTopicSection(
                    topic['title'],
                    topic['id'],
                    topicMap[topic['id']] ?? [],
                    topic: topic,
                    key: ValueKey(
                      'topic_section_${topic['id']}',
                    ), // Added Key here
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            )
            .toList(),
      ],
    );
  }

  Widget _buildTopicSection(
    String title,
    String topicKey,
    List<Map<String, dynamic>> posts, {
    Map<String, dynamic>? topic,
    Key? key,
  }) {
    final isExpanded = _expandedTopics[topicKey] ?? true;
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Container(
      key: key, // Use the key here
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(20), // Matches your dashboard cards
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
          GestureDetector(
            onTap: () =>
                setState(() => _expandedTopics[topicKey] = !isExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  // ─── Proper Icon instead of Folder Emoji ───
                  const Icon(
                    Icons.folder_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const Spacer(),
                  // Count indicator
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${posts.length}',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: textColor.withValues(alpha: 0.4),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            if (posts.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No posts in this topic yet',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: textColor.withValues(alpha: 0.4),
                  ),
                ),
              )
            else ...[
              const Divider(height: 1),
              ...posts.asMap().entries.map(
                (entry) => _buildCourseworkItem(
                  entry.value,
                  entry.key == posts.length - 1,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  void _showTopicOptions(Map<String, dynamic> topic) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${topic['title']}',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _buildOptionTile(
              Icons.delete_outline,
              'Delete Topic',
              AppColors.error,
              () async {
                Navigator.pop(context);
                await _supabase.from('topics').delete().eq('id', topic['id']);
                await _loadCoursework();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseworkItem(Map<String, dynamic> post, bool isLast) {
    final type = post['type'] as String;
    final postColor = _getPostColor(type);
    final postIcon = _getPostIcon(type);
    final hasSchedule = post['scheduled_time'] != null;
    final scheduleStatus = hasSchedule
        ? _getScheduleStatus(post['scheduled_time'])
        : 'none';

    // Using your system dark blue for light mode
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: context.borderColor.withValues(alpha: 0.5),
                ),
              ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: postColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(postIcon, color: postColor, size: 20),
        ),
        title: Text(
          post['title'] ?? '',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(
                'Posted ${_formatDate(post['created_at'])}',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: textColor.withValues(alpha: 0.5),
                ),
              ),
              if (hasSchedule) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (scheduleStatus == 'live'
                                ? const Color(0xFF22C55E)
                                : context.textHint)
                            .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        scheduleStatus == 'live'
                            ? Icons.fiber_manual_record
                            : scheduleStatus == 'upcoming'
                            ? Icons.schedule_rounded
                            : Icons.check_circle_rounded,
                        size: 10,
                        color: scheduleStatus == 'live'
                            ? const Color(0xFF22C55E)
                            : context.textHint,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        scheduleStatus == 'live'
                            ? 'Live'
                            : scheduleStatus == 'upcoming'
                            ? 'Scheduled'
                            : 'Ended',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: scheduleStatus == 'live'
                              ? const Color(0xFF22C55E)
                              : context.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        // Aligned trailing icon with instructor check
        trailing: widget.isInstructor
            ? GestureDetector(
                onTap: () => _showPostOptions(post),
                child: Icon(
                  Icons.more_vert,
                  color: textColor.withValues(alpha: 0.4),
                  size: 20,
                ),
              )
            : Icon(
                Icons.chevron_right,
                color: textColor.withValues(alpha: 0.3),
                size: 20,
              ),

        // ─── RESTORED NAVIGATION LOGIC ───
        onTap: () =>
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => post['type'] == 'assignment'
                    ? AssignmentDetailScreen(
                        post: post,
                        course: widget.course,
                        isInstructor: widget.isInstructor,
                      )
                    : PostDetailScreen(
                        post: post,
                        course: widget.course,
                        isInstructor: widget.isInstructor,
                      ),
              ),
            ).then(
              (_) => _loadCoursework(),
            ), // Reloads data when returning from the detail screen
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // PEOPLE TAB
  // ════════════════════════════════════════════════════════
  Widget _buildPeopleTab() {
    if (_isLoadingPeople) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        Text(
          'Instructors',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        Divider(color: context.borderColor),
        if (_instructor != null)
          _buildPersonTile(_instructor!, showMenu: false),
        const SizedBox(height: 20),
        Row(
          children: [
            Text(
              'Students',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_students.length}',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        Divider(color: context.borderColor),
        if (_students.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No students enrolled yet',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: context.textHint,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ..._students.map(
          (s) => _buildPersonTile(s, showMenu: widget.isInstructor),
        ),
      ],
    );
  }

  Widget _buildPersonTile(Map<String, dynamic> user, {required bool showMenu}) {
    final name = user['name'] as String? ?? 'User';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            child: Text(
              name.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: context.textPrimary,
              ),
            ),
          ),
          if (showMenu)
            GestureDetector(
              onTap: () => _showRemoveStudentDialog(user),
              child: Icon(
                Icons.more_vert,
                color: context.textSecondary,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
    // Interstellar Blue in Light Mode, White in Dark Mode
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon with soft circular tint
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 64,
                color: textColor.withValues(alpha: 0.2), // Subtle icon color
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                color: textColor.withValues(alpha: 0.5),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateTimePicker({
    required BuildContext context,
    required DateTime? date,
    required TimeOfDay? time,
    required VoidCallback onDateTap,
    required VoidCallback onTimeTap,
  }) {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);

    return Column(
      children: [
        // Date Picker Box
        GestureDetector(
          onTap: onDateTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 18,
                  color: context.textSecondary,
                ),
                const SizedBox(width: 10),
                Text(
                  date == null
                      ? 'Select Date'
                      : '${date.month}/${date.day}/${date.year}',
                  style: TextStyle(fontFamily: 'Poppins', color: textColor),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Time Picker Box
        GestureDetector(
          onTap: onTimeTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.access_time_outlined,
                  size: 18,
                  color: context.textSecondary,
                ),
                const SizedBox(width: 10),
                Text(
                  time == null ? 'Select Time' : time.format(context),
                  style: TextStyle(fontFamily: 'Poppins', color: textColor),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRankingTab() {
    final textColor = context.isDark ? Colors.white : const Color(0xFF0D1B4B);
    if (_isLoadingPeople)
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    final ranked = [..._students]
      ..sort((a, b) => (b['xp'] as int? ?? 0).compareTo(a['xp'] as int? ?? 0));
    final currentUserId = _supabase.auth.currentUser?.id;
    if (ranked.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.leaderboard_outlined,
              size: 64,
              color: textColor.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              'No students yet',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Rankings will appear once students join.',
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                color: AppColors.gold,
                size: 26,
              ),
              const SizedBox(width: 8),
              Text(
                'Class Rankings',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
        if (ranked.length >= 3) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _buildRankPodiumItem(ranked[1], 2, 100, textColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildRankPodiumItem(ranked[0], 1, 130, textColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildRankPodiumItem(ranked[2], 3, 80, textColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        ...ranked.asMap().entries.map((entry) {
          final index = entry.key;
          final student = entry.value;
          final rank = index + 1;
          final isCurrentUser = student['id'] == currentUserId;
          final xp = student['xp'] as int? ?? 0;
          final medalColors = {
            1: AppColors.gold,
            2: const Color(0xFFC0C0C0),
            3: const Color(0xFFCD7F32),
          };
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
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isCurrentUser ? Colors.transparent : context.borderColor,
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
                SizedBox(
                  width: 36,
                  child: rank <= 3
                      ? Icon(
                          Icons.workspace_premium_rounded,
                          color: medalColors[rank],
                          size: 24,
                        )
                      : Text(
                          '#$rank',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isCurrentUser
                                ? Colors.white70
                                : textColor.withValues(alpha: 0.5),
                          ),
                          textAlign: TextAlign.center,
                        ),
                ),
                const SizedBox(width: 12),
                CircleAvatar(
                  radius: 20,
                  backgroundColor: isCurrentUser
                      ? Colors.white24
                      : AppColors.primary.withValues(alpha: 0.15),
                  child: Text(
                    (student['name'] as String).substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      color: isCurrentUser ? Colors.white : AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student['name'] ?? '',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isCurrentUser ? Colors.white : textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _getLevelTitle(xp),
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$xp XP',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isCurrentUser ? Colors.white : AppColors.gold,
                      ),
                    ),
                    if (isCurrentUser)
                      const Text(
                        'You',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildRankPodiumItem(
    Map<String, dynamic> student,
    int rank,
    double height,
    Color textColor,
  ) {
    final medalColors = {
      1: AppColors.gold,
      2: const Color(0xFFC0C0C0),
      3: const Color(0xFFCD7F32),
    };
    final xp = student['xp'] as int? ?? 0;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
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
          Icon(
            Icons.workspace_premium_rounded,
            color: medalColors[rank],
            size: rank == 1 ? 28 : 22,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              (student['name'] as String).split(' ').first,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '$xp XP',
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

  String _getLevelTitle(int xp) {
    if (xp >= 2000) return 'Master';
    if (xp >= 1000) return 'Expert';
    if (xp >= 600) return 'Advanced';
    if (xp >= 300) return 'Intermediate';
    if (xp >= 100) return 'Novice';
    return 'Beginner';
  }

  Widget _buildUploadButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool isUploading,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isUploading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Icon(Icons.attach_file_outlined, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}
