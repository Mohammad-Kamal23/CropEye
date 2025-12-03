import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

const _brandGreen = Color(0xFF1B5E20);
const _pageBgTop = Color(0xFFE3F4E1);
const _pageBgBottom = Colors.white;

class ContactPage extends StatefulWidget {
  const ContactPage({super.key});
  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  final List<Map<String, dynamic>> _contacts = [
    {
      'icon': Icons.email_outlined,
      'label': 'Email',
      'value': 'moh203.kamal@gmail.com',
    },
    {
      'icon': Icons.phone_android,
      'label': 'Phone',
      'value': '+962 79 123 4567',
    },
    {
      'icon': Icons.link,
      'label': 'LinkedIn',
      'value': 'linkedin.com/in/mohammad-abdelaziz-851107292/',
    },
    {
      'icon': Icons.camera_alt_outlined,
      'label': 'Instagram',
      'value': '@cropeye.ai',
    },
    {
      'icon': Icons.code,
      'label': 'GitHub',
      'value': 'github.com/moh203',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_pageBgTop, _pageBgBottom],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          child: FadeTransition(
            opacity: _animCtrl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  "Contact Us",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: _brandGreen,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Stay connected with the CropEye team",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.black87),
                ),
                const SizedBox(height: 22),
                ListView.builder(
                  shrinkWrap: true,
                  primary: false,
                  itemCount: _contacts.length,
                  itemBuilder: (context, index) {
                    final c = _contacts[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: _brandGreen.withOpacity(0.25),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _brandGreen.withOpacity(0.15),
                                child:
                                    Icon(c['icon'], color: _brandGreen),
                              ),
                              title: Text(
                                c['label'],
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _brandGreen,
                                ),
                              ),
                              subtitle: Text(
                                c['value'],
                                style: const TextStyle(
                                    color: Colors.black87, fontSize: 14.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                        .animate(delay: (150 * index).ms)
                        .fadeIn(duration: 400.ms)
                        .slideY(begin: 0.2, end: 0);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
