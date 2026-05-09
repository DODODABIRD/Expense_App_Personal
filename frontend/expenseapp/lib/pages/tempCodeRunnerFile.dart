Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await DatabaseHelp.initDB();
    } catch(e){
      print("Nigga The Database Aint Initialized");
    }

    
    final data = await DatabaseHelp.getData();
    for (final row in data) {
      print(row);
    }


    try {
      // 1. Panggil getData() langsung dari class karena sudah static
      // Tidak perlu simpan hasil initDB() ke variabel baru
      final List<Map<String, dynamic>> data = await DatabaseHelp.getData();

      setState(() {
        // 2. Konversi List<Map> menjadi List<ExpenseModel>
        _expenses = data.map((item) => ExpenseModel.fromMap(item)).toList();
        _isLoading = false;
      });

    } catch (e) {
      print("Error loading data: $e");
      setState(() => _isLoading = false);
    }
  }