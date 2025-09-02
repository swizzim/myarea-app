import 'package:flutter/material.dart';
import 'package:myarea_app/screens/messages/conversations_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  @override
  Widget build(BuildContext context) {
    return ConversationsScreen();
  }
} 