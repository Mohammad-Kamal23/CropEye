import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_page.dart';
//import 'register_page.dart';
//import 'admin_login_page.dart';
//import 'admin_register_page.dart';
import 'design.dart'; // ✅ your original design.dart remains untouched

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final TextEditingController _emailController = TextEditingController();
  String _errorMessage = '';
  bool _isLoading = false;

  Future<void> _resetPassword() async {
    String email = _emailController.text.trim();

    if (!_isValidEmail(email)) {
      setState(() => _errorMessage = "Enter a valid email address");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;

      _showSuccessDialog();
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? "An error occurred.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  bool _isValidEmail(String email) {
    final emailRegex =
        RegExp(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$");
    return emailRegex.hasMatch(email);
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("✅ Success"),
        content:
            const Text("A password reset link has been sent to your email."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
              );
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: "Reset Password",
      subtitle: "We'll send you a reset link",
      topIcon: const TomatoBadge(size: 85),
      fields: [
        // 🔧 FIXED: removed 'keyboardType' since your old design.dart doesn’t support it
        AuthTextField(
          icon: Icons.email,
          hint: "Email Address",
          controller: _emailController,
        ),
        if (_errorMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _errorMessage,
              style: const TextStyle(color: Colors.red, fontSize: 14),
            ),
          ),
        const SizedBox(height: 20),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(10),
            child: CircularProgressIndicator(),
          ),
      ],
      buttonText: "Send Reset Link",
      onSubmit: _resetPassword,
      footerText: "Return to login?",
      footerActionText: "Back",
      onFooterAction: () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      },
    );
  }
}
