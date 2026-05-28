// lib/presentation/courses/assignment_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import 'file_viewer_screen.dart';

class AssignmentDetailScreen extends StatefulWidget {
  final Map<String, dynamic> post;
  final Map<String, dynamic> course;
  final bool isInstructor;

  const AssignmentDetailScreen({
    super.key,
    required this.post,
    required this.course,
    required this.isInstructor,
  });

  @override
  State<AssignmentDetailScreen> createState() => _AssignmentDetailScreenState();
}

class _AssignmentDetailScreenState extends State<AssignmentDetailScreen>
    with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;

  // Common
  String? _currentUserName;
  String? _currentUserId;

  // Instructor
  List<Map<String, dynamic>> _students = [];
  Map<String, Map<String, dynamic>> _submissions = {};
  bool _isLoadingStudents = true;
  bool _acceptSubmissions = true;
  Map<String, dynamic>? _selectedStudent;
  Map<String, dynamic>? _selectedSubmission;
  List<Map<String, dynamic>> _privateComments = [];
  final _gradeController = TextEditingController();
  final _privateCommentController = TextEditingController();
  bool _isSubmittingComment = false;
  bool _isGrading = false;
  bool _isLoadingPrivate = false;

  // Student
  Map<String, dynamic>? _mySubmission;
  List<Map<String, dynamic>> _myPrivateComments = [];
  final _myPrivateCommentController = TextEditingController();
  bool _isSubmittingMyComment = false;
  bool _isUploadingWork = false;
  String? _myWorkFileUrl;
  String? _myWorkFileName;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.isInstructor ? 2 : 1,
      vsync: this,
    );
    _acceptSubmissions = widget.post['accept_submissions'] ?? true;
    _loadCurrentUser();
    if (widget.isInstructor) {
      _loadStudentsAndSubmissions();
    } else {
      _loadMySubmission();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _gradeController.dispose();
    _privateCommentController.dispose();
    _myPrivateCommentController.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════
  // DATA LOADING
  // ════════════════════════════════════════════════════════

  Future<void> _loadCurrentUser() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      _currentUserId = userId;
      final data = await _supabase
          .from('users')
          .select('name')
          .eq('id', userId)
          .single();
      if (mounted) setState(() => _currentUserName = data['name']);
    } catch (e) {
      debugPrint('User: $e');
    }
  }

  Future<void> _loadMySubmission() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final assessmentId = await _getOrCreateAssessmentId();

      final submissionsData = await _supabase
          .from('submissions')
          .select()
          .eq('assessment_id', assessmentId)
          .eq('student_id', userId)
          .order('submitted_at', ascending: false, nullsFirst: false)
          .order('created_at', ascending: false, nullsFirst: false);

      Map<String, dynamic>? bestSubmission;
      for (final item in submissionsData) {
        final row = Map<String, dynamic>.from(item as Map);
        final hasSubmittedAt = row['submitted_at'] != null &&
            row['submitted_at'].toString().trim().isNotEmpty;
        final hasFile = row['file_url'] != null &&
            row['file_url'].toString().trim().isNotEmpty;

        // Priority 1: turned-in row with file
        if (hasSubmittedAt && hasFile) {
          bestSubmission = row;
          break;
        }

        // Priority 2: any turned-in row
        if (bestSubmission == null && hasSubmittedAt) {
          bestSubmission = row;
        }

        // Priority 3: draft row with attached file
        if (bestSubmission == null && hasFile) {
          bestSubmission = row;
        }

        // Priority 4: latest row
        bestSubmission ??= row;
      }

      final commentData = await _supabase
          .from('private_comments')
          .select()
          .eq('post_id', widget.post['id'])
          .eq('student_id', userId)
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _mySubmission = bestSubmission;
          _myWorkFileUrl = _mySubmission?['file_url'];
          _myWorkFileName = _mySubmission?['file_name'];
          _myPrivateComments = List<Map<String, dynamic>>.from(commentData);
          _isLoadingStudents = false;
        });
      }
    } catch (e) {
      debugPrint('Load my submission error: $e');
      if (mounted) setState(() => _isLoadingStudents = false);
    }
  }

  Future<void> _loadStudentsAndSubmissions() async {
    try {
      final enrollmentsData = await _supabase
          .from('enrollments')
          .select('student_id')
          .eq('course_id', widget.course['id']);
      final studentIds = (enrollmentsData as List)
          .map((e) => e['student_id'] as String)
          .toList();

      List<Map<String, dynamic>> studentsList = [];
      if (studentIds.isNotEmpty) {
        final studentsData = await _supabase
            .from('users')
            .select('id, name')
            .inFilter('id', studentIds);
        studentsList = List<Map<String, dynamic>>.from(studentsData);
      }

      final assessmentId = await _getOrCreateAssessmentId();

      final submissionsData = await _supabase
          .from('submissions')
          .select()
          .eq('assessment_id', assessmentId)
          .order('submitted_at', ascending: false, nullsFirst: false)
          .order('created_at', ascending: false, nullsFirst: false);

      final submissionsMap = <String, Map<String, dynamic>>{};
      for (final item in submissionsData) {
        final row = Map<String, dynamic>.from(item as Map);
        final studentId = row['student_id']?.toString();
        if (studentId == null || studentId.isEmpty) continue;

        final current = submissionsMap[studentId];
        if (current == null) {
          submissionsMap[studentId] = row;
          continue;
        }

        final rowTurnedIn = _submissionIsTurnedIn(row);
        final currentTurnedIn = _submissionIsTurnedIn(current);
        final rowHasFile = _submissionHasFile(row);
        final currentHasFile = _submissionHasFile(current);

        // Prefer turned-in rows, then rows with a file, then the newest row.
        if ((rowTurnedIn && !currentTurnedIn) ||
            (rowTurnedIn == currentTurnedIn && rowHasFile && !currentHasFile)) {
          submissionsMap[studentId] = row;
        }
      }

      if (mounted) {
        setState(() {
          _students = studentsList;
          _submissions = submissionsMap;
          if (_selectedStudent != null) {
            _selectedSubmission = _submissions[_selectedStudent!['id']?.toString()];
          }
          _isLoadingStudents = false;
        });
      }
    } catch (e) {
      debugPrint('Load students/submissions error: $e');
      if (mounted) setState(() => _isLoadingStudents = false);
    }
  }

  bool _submissionHasFile(Map<String, dynamic>? submission) {
    final fileUrl = submission?['file_url'];
    return fileUrl != null && fileUrl.toString().trim().isNotEmpty;
  }

  bool _submissionIsTurnedIn(Map<String, dynamic>? submission) {
    final submittedAt = submission?['submitted_at'];
    return submittedAt != null && submittedAt.toString().trim().isNotEmpty;
  }

  Future<Map<String, dynamic>?> _loadSingleSubmission(String studentId) async {
    try {
      final assessmentId = await _getOrCreateAssessmentId();

      final submissionsData = await _supabase
          .from('submissions')
          .select()
          .eq('assessment_id', assessmentId)
          .eq('student_id', studentId)
          .order('submitted_at', ascending: false, nullsFirst: false)
          .order('created_at', ascending: false, nullsFirst: false);

      Map<String, dynamic>? bestSubmission;
      for (final item in submissionsData) {
        final row = Map<String, dynamic>.from(item as Map);
        final rowTurnedIn = _submissionIsTurnedIn(row);
        final rowHasFile = _submissionHasFile(row);

        if (rowTurnedIn && rowHasFile) {
          bestSubmission = row;
          break;
        }
        if (bestSubmission == null) {
          bestSubmission = row;
          continue;
        }
        if ((rowTurnedIn && !_submissionIsTurnedIn(bestSubmission)) ||
            (rowTurnedIn == _submissionIsTurnedIn(bestSubmission) &&
                rowHasFile &&
                !_submissionHasFile(bestSubmission))) {
          bestSubmission = row;
        }
      }

      if (bestSubmission == null) {
        if (mounted) {
          setState(() {
            _submissions.remove(studentId);
            _selectedSubmission = null;
          });
        }
        return null;
      }

      if (mounted) {
        setState(() {
          _submissions[studentId] = bestSubmission!;
          _selectedSubmission = bestSubmission;
        });
      }
      return bestSubmission;
    } catch (e) {
      debugPrint('Load single submission error: $e');
      return _submissions[studentId];
    }
  }

  Future<void> _loadPrivateComments(String studentId) async {
    setState(() => _isLoadingPrivate = true);
    try {
      final data = await _supabase
          .from('private_comments')
          .select()
          .eq('post_id', widget.post['id'])
          .eq('student_id', studentId)
          .order('created_at', ascending: true);
      if (mounted) {
        setState(() {
          _privateComments = List<Map<String, dynamic>>.from(data);
          _isLoadingPrivate = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingPrivate = false);
    }
  }

  Future<String> _getOrCreateAssessmentId() async {
    final postId = widget.post['id']?.toString();

    if (postId == null || postId.isEmpty) {
      throw Exception('Post ID is missing. Cannot create assessment.');
    }

    final existing = await _supabase
        .from('assessments')
        .select('id')
        .eq('id', postId)
        .maybeSingle();

    if (existing != null && existing['id'] != null) {
      return existing['id'].toString();
    }

    final assessmentData = <String, dynamic>{
      'id': postId,
      'course_id': widget.course['id'],
      'title': widget.post['title'] ?? 'Assignment',
      'type': widget.post['type'] ?? 'assignment',
    };

    final moduleId =
        widget.post['module_id'] ?? widget.post['moduleId'] ?? widget.course['module_id'];
    if (moduleId != null) {
      assessmentData['module_id'] = moduleId;
    }

    try {
      await _supabase.from('assessments').insert(assessmentData);
    } on PostgrestException catch (e) {
      // 23505 means another request already created the same assessment.
      if (e.code != '23505') {
        rethrow;
      }
    }

    return postId;
  }

  // ════════════════════════════════════════════════════════
  // STUDENT ACTIONS
  // ════════════════════════════════════════════════════════

  Future<void> _pickAndUploadWork() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'png', 'jpg', 'jpeg', 'mp4'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;

    setState(() => _isUploadingWork = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('You must be logged in before uploading work.');
      }

      if (_currentUserName == null) await _loadCurrentUser();

      final assessmentId = await _getOrCreateAssessmentId();

      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final safeFileName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final storagePath =
          '$assessmentId/$userId/${DateTime.now().millisecondsSinceEpoch}_$safeFileName';

      await _supabase.storage.from('submissions').uploadBinary(storagePath, bytes);
      final url = _supabase.storage.from('submissions').getPublicUrl(storagePath);

      // IMPORTANT:
      // Uploading only attaches the file. It does NOT turn in the assignment.
      // The student must press the Turn in button after uploading.
      if (_mySubmission == null) {
        final data = await _supabase
            .from('submissions')
            .insert({
              'assessment_id': assessmentId,
              'course_id': widget.course['id'],
              'student_id': userId,
              'student_name': _currentUserName ?? 'Student',
              'type': widget.post['type'] ?? 'assignment',
              'file_url': url,
              'file_name': file.name,
              'submitted_at': null,
              'max_score': _maxPoints,
              'is_graded': false,
              'is_returned': false,
            })
            .select()
            .single();

        if (mounted) {
          setState(() {
            _mySubmission = Map<String, dynamic>.from(data);
            _myWorkFileUrl = url;
            _myWorkFileName = file.name;
          });
        }
      } else {
        await _supabase
            .from('submissions')
            .update({
              'file_url': url,
              'file_name': file.name,
              'student_name': _currentUserName ?? 'Student',
              // Keep submitted_at unchanged. If it was not turned in yet, it stays null.
              // If the teacher already graded it, the UI prevents replacing the file.
            })
            .eq('id', _mySubmission!['id']);

        if (mounted) {
          setState(() {
            _mySubmission!['file_url'] = url;
            _mySubmission!['file_name'] = file.name;
            _myWorkFileUrl = url;
            _myWorkFileName = file.name;
          });
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('File attached. Tap Turn in to submit.'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingWork = false);
    }
  }

  Future<void> _removeWork() async {
    if (_hasTurnedIn || _isGraded) return;

    if (_mySubmission == null) {
      setState(() {
        _myWorkFileUrl = null;
        _myWorkFileName = null;
      });
      return;
    }

    try {
      await _supabase
          .from('submissions')
          .update({'file_url': null, 'file_name': null})
          .eq('id', _mySubmission!['id']);

      setState(() {
        _myWorkFileUrl = null;
        _myWorkFileName = null;
        _mySubmission!['file_url'] = null;
        _mySubmission!['file_name'] = null;
      });
    } catch (e) {
      debugPrint('Remove work: $e');
    }
  }

  Future<void> _markAsDone() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('You must be logged in before submitting work.');
      }

      if (_isGraded) return;

      if (_isPastDue) {
        throw Exception('The deadline has passed. You can no longer turn in this assignment.');
      }

      final hasUploadedFile = _myWorkFileUrl != null &&
          _myWorkFileUrl.toString().trim().isNotEmpty &&
          _myWorkFileName != null &&
          _myWorkFileName.toString().trim().isNotEmpty;
      if (!hasUploadedFile) {
        throw Exception('Please upload your file before turning in the assignment.');
      }

      if (_currentUserName == null) await _loadCurrentUser();
      final assessmentId = await _getOrCreateAssessmentId();
      final now = DateTime.now().toIso8601String();

      if (_mySubmission == null) {
        final data = await _supabase
            .from('submissions')
            .insert({
              'assessment_id': assessmentId,
              'course_id': widget.course['id'],
              'student_id': userId,
              'student_name': _currentUserName ?? 'Student',
              'type': widget.post['type'] ?? 'assignment',
              'file_url': _myWorkFileUrl,
              'file_name': _myWorkFileName,
              'submitted_at': now,
              'max_score': _maxPoints,
              'is_graded': false,
              'is_returned': false,
            })
            .select()
            .single();

        if (mounted) {
          setState(() => _mySubmission = Map<String, dynamic>.from(data));
        }
      } else {
        await _supabase
            .from('submissions')
            .update({
              'submitted_at': now,
              'student_name': _currentUserName ?? 'Student',
              'file_url': _myWorkFileUrl,
              'file_name': _myWorkFileName,
              'max_score': _maxPoints,
              'is_graded': false,
              'is_returned': false,
            })
            .eq('id', _mySubmission!['id']);

        if (mounted) {
          setState(() {
            _mySubmission!['submitted_at'] = now;
            _mySubmission!['file_url'] = _myWorkFileUrl;
            _mySubmission!['file_name'] = _myWorkFileName;
            _mySubmission!['max_score'] = _maxPoints;
            _mySubmission!['is_graded'] = false;
            _mySubmission!['is_returned'] = false;
          });
        }
      }

      await _loadMySubmission();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Assignment turned in! ✅'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Turn in error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _submitMyPrivateComment() async {
    if (_myPrivateCommentController.text.trim().isEmpty) return;
    final text = _myPrivateCommentController.text.trim();
    setState(() => _isSubmittingMyComment = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      await _supabase.from('private_comments').insert({
        'post_id': widget.post['id'],
        'student_id': userId,
        'sender_id': userId,
        'sender_name': _currentUserName ?? 'Student',
        'text': text,
        'created_at': DateTime.now().toIso8601String(),
      });
      _myPrivateCommentController.clear();
      await _loadMySubmission();
    } catch (e) {
      debugPrint('Private comment: $e');
    } finally {
      if (mounted) setState(() => _isSubmittingMyComment = false);
    }
  }

  // ════════════════════════════════════════════════════════
  // INSTRUCTOR ACTIONS
  // ════════════════════════════════════════════════════════

  Future<void> _submitPrivateComment(String studentId) async {
    if (_privateCommentController.text.trim().isEmpty) return;
    final text = _privateCommentController.text.trim();
    setState(() => _isSubmittingComment = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      await _supabase.from('private_comments').insert({
        'post_id': widget.post['id'],
        'student_id': studentId,
        'sender_id': userId,
        'sender_name': _currentUserName ?? 'Instructor',
        'text': text,
        'created_at': DateTime.now().toIso8601String(),
      });
      _privateCommentController.clear();
      await _loadPrivateComments(studentId);
      await _supabase.from('notifications').insert({
        'user_id': studentId,
        'course_id': widget.course['id'],
        'post_id': widget.post['id'],
        'type': 'private_comment',
        'title': 'New private comment on ${widget.post['title']}',
        'body': text,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Instructor comment: $e');
    } finally {
      if (mounted) setState(() => _isSubmittingComment = false);
    }
  }

  Future<void> _gradeSubmission(String studentId) async {
    final score = int.tryParse(_gradeController.text.trim());
    if (score == null || score < 0 || score > _maxPoints) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Enter a valid score (0-$_maxPoints)',
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _isGrading = true);
    try {
      final submission =
          await _loadSingleSubmission(studentId) ?? _submissions[studentId] ?? _selectedSubmission;
      if (!_submissionIsTurnedIn(submission)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('This student has not turned in the assignment yet.'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      if (!_submissionHasFile(submission)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('This student turned in the assignment, but no file is attached.'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      await _supabase
          .from('submissions')
          .update({
            'score': score,
            'is_graded': true,
            'is_returned': true,
            'returned_at': DateTime.now().toIso8601String(),
          })
          .eq('id', submission!['id']);
      await _supabase.from('notifications').insert({
        'user_id': studentId,
        'course_id': widget.course['id'],
        'post_id': widget.post['id'],
        'type': 'private_comment',
        'title': '${widget.post['title']} has been graded',
        'body': 'Your score: $score/$_maxPoints',
        'created_at': DateTime.now().toIso8601String(),
      });
      await _loadStudentsAndSubmissions();
      if (mounted) {
        setState(() {
          _selectedSubmission = _submissions[studentId] ?? _selectedSubmission;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Grade submitted! ✅'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGrading = false);
    }
  }

  Future<void> _toggleAcceptSubmissions() async {
    try {
      final newValue = !_acceptSubmissions;
      await _supabase
          .from('posts')
          .update({'accept_submissions': newValue})
          .eq('id', widget.post['id']);
      if (mounted) setState(() => _acceptSubmissions = newValue);
    } catch (e) {
      debugPrint('Toggle: $e');
    }
  }

  // ════════════════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════════════════

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    final date = DateTime.parse(dateStr);
    final now = DateTime.now();
    final diff = date.difference(now);
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
    final hour = date.hour > 12
        ? date.hour - 12
        : date.hour == 0
        ? 12
        : date.hour;
    final ampm = date.hour >= 12 ? 'PM' : 'AM';
    final min = date.minute.toString().padLeft(2, '0');
    if (diff.inDays == 0) return 'Due today, $hour:$min $ampm';
    if (diff.inDays == 1) return 'Due tomorrow, $hour:$min $ampm';
    if (diff.inDays < 0)
      return 'Past due ${months[date.month - 1]} ${date.day}';
    return 'Due ${months[date.month - 1]} ${date.day}, $hour:$min $ampm';
  }

  DateTime? get _dueDate {
    final value = widget.post['due_date'];
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  bool get _isPastDue {
    final due = _dueDate;
    return due != null && DateTime.now().isAfter(due);
  }

  bool get _hasTurnedIn => _mySubmission?['submitted_at'] != null;
  bool get _hasAttachedFile => _myWorkFileUrl != null && _myWorkFileName != null;
  bool get _isGraded => _mySubmission?['is_graded'] == true;
  int get _maxPoints => int.tryParse((widget.post['points'] ?? 100).toString()) ?? 100;
  int get _turnedInCount =>
      _submissions.values.where((s) => s['submitted_at'] != null).length;
  int get _gradedCount =>
      _submissions.values.where((s) => s['is_graded'] == true).length;
  int get _assignedCount => _students.length - _turnedInCount;
  int get _returnedCount =>
      _submissions.values.where((s) => s['is_returned'] == true).length;

  // ════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: Stack(
        children: [
          Container(decoration: context.scaffoldGradient),
          SafeArea(
            child: Column(
              children: [
                // ─── Top Bar ──────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _selectedStudent != null
                            ? () => setState(() {
                                _selectedStudent = null;
                                _selectedSubmission = null;
                                _privateComments = [];
                              })
                            : () => Navigator.pop(context),
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
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          _selectedStudent != null
                              ? _selectedStudent!['name'] ?? 'Student'
                              : widget.post['title'] ?? '',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                // ─── Instructor Tabs ───────────────────────
                if (widget.isInstructor && _selectedStudent == null) ...[
                  Container(
                    color: context.cardColor,
                    child: TabBar(
                      controller: _tabController,
                      labelColor: AppColors.primary,
                      unselectedLabelColor: context.textSecondary,
                      indicatorColor: AppColors.primary,
                      indicatorWeight: 2.5,
                      labelStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                      ),
                      tabs: const [
                        Tab(text: 'Instructions'),
                        Tab(text: 'Student Work'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildInstructionsTab(),
                        _buildStudentWorkTab(),
                      ],
                    ),
                  ),
                ] else if (_selectedStudent != null) ...[
                  Expanded(child: _buildInstructorStudentView()),
                ] else ...[
                  // Student view
                  Expanded(child: _buildStudentView()),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // STUDENT VIEW (Google Classroom style)
  // ════════════════════════════════════════════════════════

  Widget _buildStudentView() {
    final dueDate = widget.post['due_date'];
    final isPastDue =
        dueDate != null && DateTime.parse(dueDate).isBefore(DateTime.now());

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── Assignment Info Header ───────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  color: context.cardColor,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (dueDate != null) ...[
                        Text(
                          _formatDate(dueDate),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            color: isPastDue
                                ? AppColors.error
                                : context.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (isPastDue || !_acceptSubmissions)
                          Text(
                            'Work cannot be turned in after the due date',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: context.textHint,
                            ),
                          ),
                        const SizedBox(height: 10),
                      ],
                      Text(
                        widget.post['title'] ?? '',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_maxPoints points',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          color: context.textSecondary,
                        ),
                      ),
                      if (_isGraded) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Grade: ${_mySubmission!['score']}/$_maxPoints',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                Divider(color: context.borderColor, height: 1),

                // ─── Instructions ─────────────────────────
                if (widget.post['instructions'] != null)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      widget.post['instructions'],
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        color: context.textPrimary,
                        height: 1.6,
                      ),
                    ),
                  ),

                // ─── Attachments (from instructor) ─────────
                if (widget.post['assessment_url'] != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Text(
                      'Attachments',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: _buildAttachmentTile(
                      widget.post['assessment_name'] ??
                          'Assignment Instructions',
                      widget.post['assessment_url'],
                      Icons.picture_as_pdf_outlined,
                      const Color(0xFFFF6B35),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // ─── Class Comments ───────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: GestureDetector(
                    onTap: () => _showClassCommentsSheet(),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Add class comment',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                Divider(color: context.borderColor),
              ],
            ),
          ),
        ),

        // ─── Your Work Bottom Sheet (sticky) ─────────────
        _buildYourWorkPanel(isPastDue),
      ],
    );
  }

  Widget _buildYourWorkPanel(bool isPastDue) {
    final canSubmit = _acceptSubmissions && !isPastDue;
    return Container(
      decoration: BoxDecoration(
        color: context.cardColor,
        border: Border(top: BorderSide(color: context.borderColor)),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.borderColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Your work',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _hasTurnedIn
                        ? Colors.green.withValues(alpha: 0.1)
                        : context.bgColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _hasTurnedIn
                          ? Colors.green.withValues(alpha: 0.4)
                          : context.borderColor,
                    ),
                  ),
                  child: Text(
                    _isGraded
                        ? 'Graded'
                        : _hasTurnedIn
                        ? 'Turned in'
                        : _hasAttachedFile
                        ? 'Attached'
                        : 'Assigned',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _isGraded
                          ? AppColors.primary
                          : _hasTurnedIn
                          ? Colors.green
                          : _hasAttachedFile
                          ? AppColors.primary
                          : context.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Attachments
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_myWorkFileName != null) ...[
                  Text(
                    'Attachments',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _myWorkFileUrl == null
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FileViewerScreen(
                                  url: _myWorkFileUrl!,
                                  fileName: _myWorkFileName!,
                                ),
                              ),
                            ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: context.bgColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.borderColor),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.insert_drive_file_outlined,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _myWorkFileName!,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                color: context.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!_hasTurnedIn && canSubmit && !_isGraded)
                            GestureDetector(
                              onTap: _removeWork,
                              child: Icon(
                                Icons.close,
                                color: context.textHint,
                                size: 18,
                              ),
                            )
                          else
                            const Icon(
                              Icons.visibility_outlined,
                              color: AppColors.primary,
                              size: 18,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ] else ...[
                  Text(
                    'Attachments',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'You have no attachments uploaded.',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: context.textHint,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],

                // Private comments
                GestureDetector(
                  onTap: () => _showPrivateCommentsSheet(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          color: Color(0xFFFF6B35),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _myPrivateComments.isEmpty
                                ? 'Add comment to ${widget.course['instructor_name'] ?? 'Instructor'}'
                                : '${_myPrivateComments.length} private comment${_myPrivateComments.length > 1 ? 's' : ''}',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              color: _myPrivateComments.isEmpty
                                  ? context.textHint
                                  : const Color(0xFFFF6B35),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Add work button
                if (canSubmit && !_hasTurnedIn && !_isGraded)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary.withValues(
                          alpha: 0.15,
                        ),
                        foregroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: BorderSide(
                            color: AppColors.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _isUploadingWork ? null : _pickAndUploadWork,
                      icon: _isUploadingWork
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            )
                          : const Icon(Icons.add, size: 20),
                      label: Text(
                        _isUploadingWork ? 'Uploading...' : 'Add work',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 8),

                // Mark as done / Unsubmit
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _hasTurnedIn || _isGraded
                          ? context.cardColor
                          : AppColors.primary,
                      foregroundColor: _hasTurnedIn || _isGraded
                          ? AppColors.primary
                          : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(
                          color: _hasTurnedIn || _isGraded
                              ? AppColors.primary
                              : Colors.transparent,
                        ),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _isGraded || _hasTurnedIn || !canSubmit
                        ? null
                        : _markAsDone,
                    child: Text(
                      _isGraded
                          ? 'Graded'
                          : _hasTurnedIn
                          ? 'Turned in'
                          : 'Turn in',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),

                if (!canSubmit && !_hasTurnedIn)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Center(
                      child: Text(
                        'Work cannot be turned in after the due date',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: context.textHint,
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showClassCommentsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
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
              padding: const EdgeInsets.all(16),
              child: Text(
                'Class Comments',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
            ),
            Divider(color: context.borderColor, height: 1),
            Expanded(
              child: Center(
                child: Text(
                  'No class comments yet.',
                  style: TextStyle(
                    color: context.textHint,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPrivateCommentsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            height: MediaQuery.of(ctx).size.height * 0.75,
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
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
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        color: Color(0xFFFF6B35),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Private Comments',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(color: context.borderColor, height: 1),
                Expanded(
                  child: _myPrivateComments.isEmpty
                      ? Center(
                          child: Text(
                            'No private comments yet.',
                            style: TextStyle(
                              color: context.textHint,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _myPrivateComments.length,
                          itemBuilder: (ctx, i) {
                            final c = _myPrivateComments[i];
                            final isOwn = c['sender_id'] == _currentUserId;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: isOwn
                                    ? MainAxisAlignment.end
                                    : MainAxisAlignment.start,
                                children: [
                                  if (!isOwn) ...[
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor: const Color(
                                        0xFFFF6B35,
                                      ).withValues(alpha: 0.15),
                                      child: Text(
                                        (c['sender_name'] as String)
                                            .substring(0, 1)
                                            .toUpperCase(),
                                        style: const TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFFFF6B35),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isOwn
                                            ? AppColors.primary.withValues(
                                                alpha: 0.1,
                                              )
                                            : context.cardColor,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isOwn
                                              ? AppColors.primary.withValues(
                                                  alpha: 0.2,
                                                )
                                              : context.borderColor,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: isOwn
                                            ? CrossAxisAlignment.end
                                            : CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            c['sender_name'] ?? '',
                                            style: TextStyle(
                                              fontFamily: 'Poppins',
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: isOwn
                                                  ? AppColors.primary
                                                  : context.textSecondary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            c['text'] ?? '',
                                            style: TextStyle(
                                              fontFamily: 'Poppins',
                                              fontSize: 13,
                                              color: context.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (isOwn) const SizedBox(width: 8),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _myPrivateCommentController,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            color: context.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText:
                                'Add comment to ${widget.course['instructor_name'] ?? 'Instructor'}',
                            hintStyle: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              color: context.textHint,
                            ),
                            filled: true,
                            fillColor: context.bgColor,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide(
                                color: context.borderColor,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide(
                                color: context.borderColor,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: const BorderSide(
                                color: Color(0xFFFF6B35),
                                width: 1.5,
                              ),
                            ),
                            suffixIcon: GestureDetector(
                              onTap: () async {
                                await _submitMyPrivateComment();
                                setSheet(() {});
                              },
                              child: _isSubmittingMyComment
                                  ? const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFFFF6B35),
                                        ),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.send_rounded,
                                      color: Color(0xFFFF6B35),
                                      size: 20,
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
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // INSTRUCTOR VIEWS
  // ════════════════════════════════════════════════════════

  Widget _buildInstructionsTab() {
    final dueDate = widget.post['due_date'];
    final isPastDue =
        dueDate != null && DateTime.parse(dueDate).isBefore(DateTime.now());

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Header (Google Classroom style) ─────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            color: context.cardColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (dueDate != null) ...[
                  Text(
                    _formatDate(dueDate),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: isPastDue
                          ? AppColors.error
                          : context.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'Work cannot be turned in after the due date',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: context.textHint,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  widget.post['title'] ?? '',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.post['points'] ?? 100} points',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          Divider(color: context.borderColor, height: 1),

          // ─── Instructions ─────────────────────────────────
          if (widget.post['instructions'] != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Do this assignment',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: context.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.post['instructions'],
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: context.textPrimary,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),

          // ─── Attachments ──────────────────────────────────
          if (widget.post['assessment_url'] != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                'Attachments',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: _buildAttachmentTile(
                widget.post['assessment_name'] ?? 'Assignment Instructions',
                widget.post['assessment_url'],
                Icons.assignment_outlined,
                const Color(0xFFFF6B35),
              ),
            ),
          ],

          Divider(color: context.borderColor, height: 1),

          // ─── Class Comments ────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text(
              'Class comments',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
            child: Text(
              'No comments',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: context.textHint,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentWorkTab() {
    if (_isLoadingStudents)
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );

    final turnedInStudents = _students
        .where((s) => _submissions[s['id']]?['submitted_at'] != null)
        .toList()
      ..sort((a, b) {
        final aSub = _submissions[a['id']];
        final bSub = _submissions[b['id']];
        final aGraded = aSub?['is_graded'] == true;
        final bGraded = bSub?['is_graded'] == true;
        if (aGraded && bGraded) {
          final aScore = int.tryParse((aSub?['score'] ?? 0).toString()) ?? 0;
          final bScore = int.tryParse((bSub?['score'] ?? 0).toString()) ?? 0;
          return bScore.compareTo(aScore);
        }
        if (aGraded != bGraded) return aGraded ? -1 : 1;
        return (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString());
      });
    final assignedStudents = _students
        .where((s) => _submissions[s['id']]?['submitted_at'] == null)
        .toList();

    return Column(
      children: [
        // ─── Stats Bar (Google Classroom style) ────────────
        Container(
          color: context.cardColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$_turnedInCount',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    Text(
                      'Turned in',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 40, color: context.borderColor),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$_assignedCount',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    Text(
                      'Assigned',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 40, color: context.borderColor),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$_gradedCount',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    Text(
                      'Graded',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 40, color: context.borderColor),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$_returnedCount',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    Text(
                      'Returned',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        Divider(color: context.borderColor, height: 1),

        Expanded(
          child: ListView(
            children: [
              // ─── Submissions close info ─────────────────
              if (widget.post['due_date'] != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _acceptSubmissions
                              ? 'Submissions will close ${_formatDate(widget.post['due_date']).replaceAll('Due ', '')}'
                              : 'Submissions are closed',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            color: context.textSecondary,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _toggleAcceptSubmissions,
                        child: Icon(
                          _acceptSubmissions
                              ? Icons.edit_outlined
                              : Icons.lock_open_outlined,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _acceptSubmissions
                              ? 'Accepting submissions'
                              : 'Submissions are closed',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            color: context.textSecondary,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _toggleAcceptSubmissions,
                        child: Icon(
                          _acceptSubmissions
                              ? Icons.lock_open_outlined
                              : Icons.lock_outline,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),

              // ─── All Students header with checkbox ──────
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.people_outlined,
                      color: context.textSecondary,
                      size: 22,
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'All students',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),

              Divider(color: context.borderColor),

              // ─── Turned In section ───────────────────────
              if (turnedInStudents.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'TURNED IN',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.textSecondary,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                ..._buildStudentRows(turnedInStudents),
                Divider(color: context.borderColor),
              ],

              // ─── Assigned section ────────────────────────
              if (assignedStudents.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'ASSIGNED',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.textSecondary,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                ..._buildStudentRows(assignedStudents),
              ],

              if (_students.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'No students enrolled yet.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: context.textHint,
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildStudentRows(List<Map<String, dynamic>> students) {
    return students.map((student) {
      final submission = _submissions[student['id']];
      final hasTurnedIn = _submissionIsTurnedIn(submission);
      final hasFile = _submissionHasFile(submission);
      final isGradedS = submission?['is_graded'] == true;

      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
          child: Text(
            (student['name'] as String).substring(0, 1).toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
        title: Text(
          student['name'] ?? '',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: context.textPrimary,
          ),
        ),
        trailing: Text(
          isGradedS
              ? '${submission!['score']}/$_maxPoints'
              : hasTurnedIn
              ? 'Turned in'
              : hasFile
              ? 'Draft attached'
              : 'Assigned',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: isGradedS
                ? AppColors.primary
                : hasTurnedIn
                ? Colors.green
                : hasFile
                ? const Color(0xFFFF6B35)
                : context.textSecondary,
          ),
        ),
        onTap: () async {
          setState(() {
            _selectedStudent = student;
            _selectedSubmission = submission;
            _gradeController.clear();
            if (submission?['score'] != null) {
              _gradeController.text = submission!['score'].toString();
            }
          });
          final freshSubmission = await _loadSingleSubmission(student['id']);
          if (freshSubmission?['score'] != null && mounted) {
            setState(() => _gradeController.text = freshSubmission!['score'].toString());
          }
          _loadPrivateComments(student['id']);
        },
      );
    }).toList();
  }

  Widget _buildInstructorStudentView() {
    final student = _selectedStudent!;
    final submission = _submissions[student['id']] ?? _selectedSubmission;
    final hasTurnedIn = _submissionIsTurnedIn(submission);
    final hasFile = _submissionHasFile(submission);
    final isGradedS = submission?['is_graded'] == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Student info + submission
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: AppColors.primary.withValues(
                        alpha: 0.15,
                      ),
                      child: Text(
                        (student['name'] as String)
                            .substring(0, 1)
                            .toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
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
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                          ),
                          Text(
                            hasTurnedIn
                                ? 'Turned in'
                                : hasFile
                                ? 'File attached, not turned in'
                                : 'Not submitted',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: hasTurnedIn
                                  ? Colors.green
                                  : hasFile
                                  ? const Color(0xFFFF6B35)
                                  : context.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (submission != null && hasFile) ...[
                  const SizedBox(height: 14),
                  Divider(color: context.borderColor, height: 1),
                  const SizedBox(height: 12),
                  Text(
                    hasTurnedIn ? 'Submitted Work' : 'Attached File (Not Turned In Yet)',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildAttachmentTile(
                    submission['file_name'] ?? 'Submission',
                    submission['file_url'],
                    Icons.insert_drive_file_outlined,
                    AppColors.primary,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Grade input
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Grade',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                if (!hasTurnedIn) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.bgColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Text(
                      hasFile
                          ? 'The student has an attached file, but it is not turned in yet. You can view the file, but grading is enabled only after the student taps Turn in.'
                          : 'No file has been attached or turned in yet.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: context.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (isGradedS) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Current Score',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            color: context.textPrimary,
                          ),
                        ),
                        Text(
                          '${submission!['score']}/$_maxPoints',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _gradeController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: context.textPrimary,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          labelText:
                              '${isGradedS ? 'Update' : 'Set'} Score (0-$_maxPoints)',
                          labelStyle: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            color: context.textSecondary,
                          ),
                          prefixIcon: Icon(
                            Icons.grade_outlined,
                            color: context.textHint,
                            size: 20,
                          ),
                          suffixText: '/ $_maxPoints',
                          suffixStyle: TextStyle(
                            fontFamily: 'Poppins',
                            color: context.textSecondary,
                          ),
                          filled: true,
                          fillColor: context.bgColor,
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
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        minimumSize: const Size(80, 52),
                        elevation: 0,
                      ),
                      onPressed: _isGrading || !hasTurnedIn
                          ? null
                          : () => _gradeSubmission(student['id']),
                      child: _isGrading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              !hasTurnedIn
                                  ? 'Waiting'
                                  : isGradedS
                                  ? 'Update'
                                  : 'Grade',
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Private comments
          Container(
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFFF6B35).withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        color: Color(0xFFFF6B35),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Private Comments',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(color: context.borderColor, height: 1),
                if (_isLoadingPrivate)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                else if (_privateComments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No private comments yet.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: context.textHint,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ..._privateComments.map((c) {
                    final isOwn = c['sender_id'] == _currentUserId;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: isOwn
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        children: [
                          if (!isOwn) ...[
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: const Color(
                                0xFFFF6B35,
                              ).withValues(alpha: 0.15),
                              child: Text(
                                (c['sender_name'] as String)
                                    .substring(0, 1)
                                    .toUpperCase(),
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFFF6B35),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isOwn
                                    ? AppColors.primary.withValues(alpha: 0.1)
                                    : context.bgColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isOwn
                                      ? AppColors.primary.withValues(alpha: 0.2)
                                      : context.borderColor,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: isOwn
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c['sender_name'] ?? '',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isOwn
                                          ? AppColors.primary
                                          : context.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    c['text'] ?? '',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 13,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (isOwn) const SizedBox(width: 8),
                        ],
                      ),
                    );
                  }),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: const Color(
                          0xFFFF6B35,
                        ).withValues(alpha: 0.15),
                        child: Text(
                          (_currentUserName ?? 'I')
                              .substring(0, 1)
                              .toUpperCase(),
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFF6B35),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _privateCommentController,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            color: context.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Add private comment...',
                            hintStyle: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              color: context.textHint,
                            ),
                            filled: true,
                            fillColor: context.bgColor,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(
                                color: context.borderColor,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(
                                color: context.borderColor,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: const BorderSide(
                                color: Color(0xFFFF6B35),
                                width: 1.5,
                              ),
                            ),
                            suffixIcon: GestureDetector(
                              onTap: () => _submitPrivateComment(student['id']),
                              child: _isSubmittingComment
                                  ? const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFFFF6B35),
                                        ),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.send_rounded,
                                      color: Color(0xFFFF6B35),
                                      size: 20,
                                    ),
                            ),
                          ),
                          onSubmitted: (_) =>
                              _submitPrivateComment(student['id']),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ─── Shared Widgets ───────────────────────────────────────

  Widget _buildAttachmentTile(
    String name,
    String url,
    IconData icon,
    Color color,
  ) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FileViewerScreen(url: url, fileName: name),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
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
            Icon(Icons.visibility_outlined, color: color, size: 16),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              color: color.withValues(alpha: 0.5),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
