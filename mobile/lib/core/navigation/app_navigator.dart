import 'package:flutter/material.dart';

/// Lets widgets mounted above [MaterialApp]'s Navigator (such as the global
/// mini-player overlay) open routes safely.
final appNavigatorKey = GlobalKey<NavigatorState>();
