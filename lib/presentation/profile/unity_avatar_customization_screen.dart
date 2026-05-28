import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_embed_unity/flutter_embed_unity.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UnityAvatarCustomizationScreen extends StatefulWidget {
  const UnityAvatarCustomizationScreen({super.key});

  @override
  State<UnityAvatarCustomizationScreen> createState() =>
      _UnityAvatarCustomizationScreenState();
}

class _UnityAvatarCustomizationScreenState
    extends State<UnityAvatarCustomizationScreen> {
  final _supabase = Supabase.instance.client;

  @override
void initState() {
  super.initState();

  // Force landscape
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Hide status/navigation bars
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
  );
}

  Future<void> _saveAvatar(Map<String, dynamic> data) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    await _supabase.from('avatar_customizations').upsert({
      'user_id': userId,
      'tshirt': data['tshirt'],
      'pants': data['pants'],
      'shoes': data['shoes'],
      'updated_at': DateTime.now().toIso8601String(),
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Avatar saved!'),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onUnityMessage(String message) async {
  try {
    final data = jsonDecode(message);

    if (data['type'] == 'save_avatar') {
      await _saveAvatar(data);
    }

    if (data['type'] == 'back_to_profile') {
      if (mounted) Navigator.pop(context, true);
    }
  } catch (e) {
    debugPrint('Unity message error: $e');
  }
}

@override
void dispose() {
  // Return to portrait
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Restore system UI
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );

  super.dispose();
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: EmbedUnity(
        onMessageFromUnity: _onUnityMessage,
      ),
    );
  }
}