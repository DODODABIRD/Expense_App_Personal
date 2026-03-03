
import 'package:flutter/material.dart';
// import 'pages/homepage.dart';
import 'pages/hp2.dart';
// import 'pages/homepage.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
	const MyApp({super.key});

	@override
	Widget build(BuildContext context) {
		return MaterialApp(
			title: 'Expense App',
			debugShowCheckedModeBanner: false,
			theme: ThemeData(
				primarySwatch: Colors.blue,
			),
			home: HomePage2(),
		);
	}
}

