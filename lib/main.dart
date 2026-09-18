import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/firebase_runtime.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try{await FirebaseRuntime.initialize();runApp(const ProviderScope(child:LeanGuardApp()));}
  catch(_){runApp(MaterialApp(home:Scaffold(body:SafeArea(child:Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.cloud_off_outlined,size:54),const SizedBox(height:20),const Text('LeanGuard could not initialize its secure connection. Check the Firebase configuration and try again.',textAlign:TextAlign.center),const SizedBox(height:20),FilledButton(onPressed:main,child:const Text('Retry'))])))))));}
}
