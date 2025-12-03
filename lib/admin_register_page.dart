import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admin_login_page.dart';
import 'design.dart'; // ✅ unified Cropeye design

class AdminRegisterPage extends StatefulWidget {
  const AdminRegisterPage({super.key});

  @override
  _AdminRegisterPageState createState() => _AdminRegisterPageState();
}

class _AdminRegisterPageState extends State<AdminRegisterPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  String _errorMessage = '';
  bool _isLoading = false;

  Future<void> _registerAdmin() async {
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();
    String confirmPassword = _confirmPasswordController.text.trim();
    String name = _nameController.text.trim();

    if (!email.contains('@admin')) {
      setState(() => _errorMessage =
          "Email must contain '@admin' for admin registration.");
      return;
    }
    if (name.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      setState(() => _errorMessage = "All fields are required.");
      return;
    }
    if (password.length < 6) {
      setState(() => _errorMessage =
          "Password must be at least 6 characters long.");
      return;
    }
    if (password != confirmPassword) {
      setState(() => _errorMessage = "Passwords do not match.");
      return;
    }

    try {
      setState(() {
        _errorMessage = '';
        _isLoading = true;
      });

      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("✅ Registration Successful"),
          content: Text("Welcome, $name! You have registered as an admin."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminLoginPage()),
                );
              },
              child: const Text("OK"),
            ),
          ],
        ),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? "An error occurred.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: "Hello Admin",
      subtitle: "Sign up!",
      fields: [
        AuthTextField(
          icon: Icons.person,
          hint: "Full Name",
          controller: _nameController,
        ),
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
        AuthTextField(
          icon: Icons.lock_outline,
          hint: "Confirm Password",
          controller: _confirmPasswordController,
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
        const SizedBox(height: 20),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(10),
            child: CircularProgressIndicator(),
          ),
      ],
      buttonText: "Sign Up",
      onSubmit: _registerAdmin,
      footerText: "Already have an admin account?",
      footerActionText: "Sign In",
      onFooterAction: () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminLoginPage()),
        );
      },
      topIcon: const TomatoBadge(size: 90), // 🍅 unified tomato logo
    );
  }
}
