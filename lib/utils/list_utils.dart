class ListUtils {
  static List<List<T>> split<T>(List<T> list, int n) {
    var out = <List<T>>[];
    var i = 0;
    while (i < list.length) {
      var end = (i + n < list.length) ? i + n : list.length;
      out.add(list.sublist(i, end));
      i += n;
    }
    return out;
  }

  static doesContainContiguous<T>(List<int> list) {
    var sorted = list.toList()..sort();
    for (var i = 0; i < sorted.length - 1; i++) {
      if (sorted[i] + 1 != sorted[i + 1]) {
        return false;
      }
    }
    return true;
  }

  static bool isContiguous<T>(List<T> list, List<T> values) {
    if (list.isEmpty) return false;

    List<int> indices = list.map((e) => values.indexOf(e)).toList();
    indices.sort();

    for (int i = 0; i < indices.length - 1; i++) {
      if (indices[i + 1] - indices[i] != 1) {
        return false;
      }
    }
    return true;
  }
}