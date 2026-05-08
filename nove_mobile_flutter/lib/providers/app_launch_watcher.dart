import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../models/sticky_note.dart';
import 'sticky_notes_provider.dart';

// 1. GLOBAL CACHE: Survives Hot Reloads and prevents duplicate stream errors
final Stream<dynamic> _sharedAppLaunchStream = 
    const EventChannel('com.nove.app_launch_events').receiveBroadcastStream().asBroadcastStream();

final appLaunchWatcherProvider = Provider((ref) => AppLaunchWatcher(ref));

class AppLaunchWatcher {
  final Ref ref;
  StreamSubscription? _subscription;

  AppLaunchWatcher(this.ref) {
    _initWatcher();
    
    ref.onDispose(() {
      _subscription?.cancel();
    });
  }

  void _initWatcher() {
    // 2. Listen to the shared broadcast stream instead of opening a new one
    _subscription = _sharedAppLaunchStream.listen((event) async {
      final eventStr = event.toString();

      if (eventStr == "close") {
        try {
          await FlutterOverlayWindow.closeOverlay();
        } catch (_) {}
        ref.read(poppedOutNoteProvider.notifier).state = null;
        return;
      }

      if (eventStr.startsWith("open:")) {
        final packageName = eventStr.substring(5);
        final notes = ref.read(stickyNotesProvider);
        
        StickyNote? linkedNote;
        try {
          linkedNote = notes.firstWhere((note) => note.linkedApp?.packageName == packageName);
        } catch (_) {
          return; 
        }

        try {
          final data = jsonEncode({
            'id': linkedNote.id,
            'title': linkedNote.title,
            'content': linkedNote.content,
            'color': _getColorValue(linkedNote.color),
            'isBubble': true, 
          });

          bool isActive = false;
          try {
            isActive = await FlutterOverlayWindow.isActive();
          } catch (_) {}

          if (!isActive) {
            await FlutterOverlayWindow.showOverlay(
              enableDrag: true,
              height: 100,
              width: 100,
              alignment: OverlayAlignment.centerRight,
            );
            await Future.delayed(const Duration(milliseconds: 400));
          } else {
            await FlutterOverlayWindow.resizeOverlay(100, 100, true);
          }
          
          await FlutterOverlayWindow.shareData("note:$data");
          ref.read(poppedOutNoteProvider.notifier).state = linkedNote;
          
        } catch (e) {
          debugPrint("Auto-Launch Overlay Error: $e");
        }
      }
    }, onError: (e) {
      debugPrint("AppLaunch Stream Error: $e");
    });
  }

  int _getColorValue(StickyColor color) {
    switch (color) {
      case StickyColor.yellow: return 0xFFF5C842;
      case StickyColor.pink: return 0xFFF2C2D8;
      case StickyColor.green: return 0xFFC5EDBE;
      case StickyColor.blue: return 0xFFB3E5FC;
    }
  }
}