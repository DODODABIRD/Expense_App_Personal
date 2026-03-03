import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar(),
      body: Column(
        children: [
          Container(
            margin: EdgeInsets.all(30),
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: const Color.fromARGB(255, 223, 223, 223),
                  blurRadius: 20,
                  spreadRadius: 0.0,
                ),
              ],
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Cari Kontol terdekat',
                filled: true,
                fillColor: const Color.fromARGB(255, 255, 255, 255),
                contentPadding: EdgeInsets.all(10),
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(8),
                  child: SvgPicture.asset(
                    'assets/icons/kontol.svg',
                    width: 5,
                    height: 5,
                  ),
                ),
                suffixIcon: Container(
                  width: 100,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(3),
                        child: SvgPicture.asset(
                          'assets/icons/kontol.svg',
                          width: 30,
                        ),
                      ),
                    ],
                  ),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  AppBar appBar() {
    return AppBar(
      title: Text(
        'Kontol Finder',
        style: TextStyle(
          color: Colors.black,
          fontSize: 30.5,
          fontWeight: FontWeight.bold,
          fontFamily: 'Courier'
        ),
      ),
      centerTitle: true,
      backgroundColor: Colors.white,
      leading: GestureDetector(
        onTap: () {},
        child: Container(
          alignment: Alignment.center,
          margin: EdgeInsets.all(14),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: SvgPicture.asset(
              'assets/icons/kontol.svg',
              height: 15,
              width: 5,
            ),
          ),
          decoration: BoxDecoration(
            color: const Color.fromARGB(255, 143, 143, 143),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      actions: [
        GestureDetector(
          child: Container(
            margin: EdgeInsets.all(4),
            alignment: Alignment.center,
            child: SvgPicture.asset(
              'assets/icons/kontol.svg',
              height: 5,
              width: 5,
            ),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 143, 143, 143),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }
}
