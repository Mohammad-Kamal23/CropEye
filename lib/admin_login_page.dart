import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admin_register_page.dart';
import 'reset_password_page.dart';
import 'homepage.dart';
import 'design.dart'; // 🍅 unified Cropeye design

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  _AdminLoginPageState createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String _errorMessage = '';
  bool _isLoading = false;

  Future<void> _loginAdmin() async {
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();

    if (!email.contains('@admin')) {
      setState(() => _errorMessage =
          "Only admin emails are allowed (must contain '@admin').");
      return;
    }

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = "Please fill in all fields.");
      return;
    }

    try {
      setState(() {
        _errorMessage = '';
        _isLoading = true;
      });

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = e.message ?? "An error occurred.";
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: "Welcome Back!",
      subtitle: "Admin Sign In",
      fields: [
        AuthTextField(
          icon: Icons.email,
          hint: "Admin Email",
          controller: _emailController,
        ),
        AuthTextField(
          icon: Icons.lock,
          hint: "Password",
          controller: _passwordController,
          obscure: true,
        ),
        if (_errorMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _errorMessage,
              style: const TextStyle(color: Colors.red, fontSize: 14),
            ),
          ),
        const SizedBox(height: 10),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: CircularProgressIndicator(),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ResetPasswordPage()),
              ),
              child: const Text(
                "Forgot Password?",
                style: TextStyle(
                  color: Color(0xFFE53935),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
      buttonText: "Sign In",
      onSubmit: _loginAdmin,
      footerText: "Don't have an admin account?",
      footerActionText: "Sign up",
      onFooterAction: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminRegisterPage()),
        );
      },
      topIcon: const TomatoBadge(size: 90), // 🍅 consistent Cropeye logo
    );
  }
}
