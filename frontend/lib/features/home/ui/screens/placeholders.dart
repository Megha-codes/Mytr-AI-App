import 'package:flutter/material.dart';
import '../../../../core/widgets/dark_header.dart';



class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Column(
        children: [
          DarkHeader(title: 'Your Profile'),
          Expanded(child: Center(child: Text('Profile Settings Screen'))),
        ],
      ),
    );
  }
}
