// Sets the sortOrder using fractional indexes.
// The newIndex item is the one that would need to be saved after this.

import 'package:dreamic/data/models_bases/sortable.dart';

class SortingHelpers {
  static int reorderItems<T extends Sortable>(List<T> items, int oldIndex, int newIndex) {
    double newSortOrder;

    //TODO: This might be necessary only because of the Flutter reorderable list.
    // if (newIndex > oldIndex) {
    //   newIndex -= 1;
    // }

    if (oldIndex < newIndex) {
      // Moving down the list.
      double nextSortOrder = newIndex + 1 < items.length
          ? items[newIndex + 1].sortOrder
          : items[newIndex].sortOrder + 1;
      newSortOrder = (items[newIndex].sortOrder + nextSortOrder) / 2;
    } else {
      // Moving up the list.
      double previousSortOrder =
          newIndex - 1 >= 0 ? items[newIndex - 1].sortOrder : items[newIndex].sortOrder - 1;
      newSortOrder = (items[newIndex].sortOrder + previousSortOrder) / 2;
    }

    items[oldIndex].sortOrder = newSortOrder;

    items.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return newIndex;
  }

  static double calculateNewSortOrder<T extends Sortable>(
      List<T> items, int oldIndex, int newIndex, SortOrderType sortOrderType) {
    double newSortOrder;

    //TODO: This might be necessary only because of the Flutter reorderable list.
    // if (newIndex > oldIndex) {
    //   newIndex -= 1;
    // }

    if (oldIndex < newIndex) {
      // Moving down the list.
      double nextSortOrder = newIndex + 1 < items.length
          ? items[newIndex + 1].sortOrder
          : items[newIndex].sortOrder + 1;
      newSortOrder = (items[newIndex].sortOrder + nextSortOrder) / 2;
    } else {
      // Moving up the list.
      double previousSortOrder =
          newIndex - 1 >= 0 ? items[newIndex - 1].sortOrder : items[newIndex].sortOrder - 1;
      newSortOrder = (items[newIndex].sortOrder + previousSortOrder) / 2;
    }

    return newSortOrder;
  }

  static double findHighestSortOrder<T extends Sortable>(List<T> items) {
    if (items.isEmpty) {
      return 0;
    }
    return items.reduce((a, b) => a.sortOrder > b.sortOrder ? a : b).sortOrder;
  }

  static double findLowestSortOrder<T extends Sortable>(List<T> items) {
    if (items.isEmpty) {
      return 0;
    }
    return items.reduce((a, b) => a.sortOrder < b.sortOrder ? a : b).sortOrder;
  }
}

enum SortOrderType { sortOrder1, sortOrder2 }

class SortingHelpers2 {
  static int reorderItems<T extends Sortable2>(
      List<T> items, int oldIndex, int newIndex, SortOrderType sortOrderType) {
    double newSortOrder;

    //TODO: This might be necessary only because of the Flutter reorderable list.
    // if (newIndex > oldIndex) {
    //   newIndex -= 1;
    // }

    if (sortOrderType == SortOrderType.sortOrder1) {
      if (oldIndex < newIndex) {
        // Moving down the list.
        double nextSortOrder = newIndex + 1 < items.length
            ? items[newIndex + 1].sortOrder1
            : items[newIndex].sortOrder1 + 1;
        newSortOrder = items[newIndex].sortOrder1 != 0
            ? (items[newIndex].sortOrder1 + nextSortOrder) / 2
            : nextSortOrder / 2;
      } else {
        // Moving up the list.
        double previousSortOrder =
            newIndex - 1 >= 0 ? items[newIndex - 1].sortOrder1 : items[newIndex].sortOrder1 - 1;
        newSortOrder = items[newIndex].sortOrder1 != 0
            ? (items[newIndex].sortOrder1 + previousSortOrder) / 2
            : previousSortOrder / 2;
      }

      items[oldIndex].sortOrder1 = newSortOrder;
    } else {
      if (oldIndex < newIndex) {
        // Moving down the list.
        double nextSortOrder = newIndex + 1 < items.length
            ? items[newIndex + 1].sortOrder2
            : items[newIndex].sortOrder2 + 1;
        newSortOrder = items[newIndex].sortOrder2 != 0
            ? (items[newIndex].sortOrder2 + nextSortOrder) / 2
            : nextSortOrder / 2;
      } else {
        // Moving up the list.
        double previousSortOrder =
            newIndex - 1 >= 0 ? items[newIndex - 1].sortOrder2 : items[newIndex].sortOrder2 - 1;
        newSortOrder = items[newIndex].sortOrder2 != 0
            ? (items[newIndex].sortOrder2 + previousSortOrder) / 2
            : previousSortOrder / 2;
      }

      items[oldIndex].sortOrder2 = newSortOrder;
    }

    items.sort((a, b) => sortOrderType == SortOrderType.sortOrder1
        ? a.sortOrder1.compareTo(b.sortOrder1)
        : a.sortOrder2.compareTo(b.sortOrder2));

    return newIndex;

    // if (oldIndex < newIndex) {
    //   // Moving down the list.
    //   double nextSortOrder = newIndex + 1 < items.length
    //       ? sortOrderType == SortOrderType.sortOrder1
    //           ? items[newIndex + 1].sortOrder1
    //           : items[newIndex + 1].sortOrder2
    //       : sortOrderType == SortOrderType.sortOrder1
    //           ? items[newIndex].sortOrder1 + 1
    //           : items[newIndex].sortOrder2 + 1;
    //   newSortOrder = (sortOrderType == SortOrderType.sortOrder1
    //           ? items[newIndex].sortOrder1
    //           : items[newIndex].sortOrder2 + nextSortOrder) /
    //       2;
    // } else {
    //   // Moving up the list.
    //   double previousSortOrder = newIndex - 1 >= 0
    //       ? sortOrderType == SortOrderType.sortOrder1
    //           ? items[newIndex - 1].sortOrder1
    //           : items[newIndex - 1].sortOrder2
    //       : sortOrderType == SortOrderType.sortOrder1
    //           ? items[newIndex].sortOrder1 - 1
    //           : items[newIndex].sortOrder2 - 1;
    //   newSortOrder = (sortOrderType == SortOrderType.sortOrder1
    //           ? items[newIndex].sortOrder1
    //           : items[newIndex].sortOrder2 + previousSortOrder) /
    //       2;
    // }

    // if (sortOrderType == SortOrderType.sortOrder1) {
    //   items[oldIndex].sortOrder1 = newSortOrder;
    // } else {
    //   items[oldIndex].sortOrder2 = newSortOrder;
    // }

    // items.sort((a, b) => sortOrderType == SortOrderType.sortOrder1
    //     ? a.sortOrder1.compareTo(b.sortOrder1)
    //     : a.sortOrder2.compareTo(b.sortOrder2));
  }

  // This expects the items to be sorted by sortOrder1 or sortOrder2.
  static double calculateNewSortOrder2<T extends Sortable2>(
      List<T> items, int oldIndex, int newIndex, SortOrderType sortOrderType) {
    double newSortOrder;

    //TODO: This might be necessary only because of the Flutter reorderable list.
    // if (newIndex > oldIndex) {
    //   newIndex -= 1;
    // }

    if (sortOrderType == SortOrderType.sortOrder1) {
      if (oldIndex < newIndex) {
        // Moving down the list.
        double nextSortOrder = newIndex + 1 < items.length
            ? items[newIndex + 1].sortOrder1
            : items[newIndex].sortOrder1 + 1;
        newSortOrder = items[newIndex].sortOrder1 != 0
            ? (items[newIndex].sortOrder1 + nextSortOrder) / 2
            : nextSortOrder / 2;
      } else {
        // Moving up the list.
        double previousSortOrder =
            newIndex - 1 >= 0 ? items[newIndex - 1].sortOrder1 : items[newIndex].sortOrder1 - 1;
        newSortOrder = items[newIndex].sortOrder1 != 0
            ? (items[newIndex].sortOrder1 + previousSortOrder) / 2
            : previousSortOrder / 2;
      }

      // items[oldIndex].sortOrder1 = newSortOrder;
    } else {
      if (oldIndex < newIndex) {
        // Moving down the list.
        double nextSortOrder = newIndex + 1 < items.length
            ? items[newIndex + 1].sortOrder2
            : items[newIndex].sortOrder2 + 1;
        newSortOrder = items[newIndex].sortOrder2 != 0
            ? (items[newIndex].sortOrder2 + nextSortOrder) / 2
            : nextSortOrder / 2;
      } else {
        // Moving up the list.
        double previousSortOrder =
            newIndex - 1 >= 0 ? items[newIndex - 1].sortOrder2 : items[newIndex].sortOrder2 - 1;
        newSortOrder = items[newIndex].sortOrder2 != 0
            ? (items[newIndex].sortOrder2 + previousSortOrder) / 2
            : previousSortOrder / 2;
      }

      // items[oldIndex].sortOrder2 = newSortOrder;
    }

    // items.sort((a, b) => sortOrderType == SortOrderType.sortOrder1
    //     ? a.sortOrder1.compareTo(b.sortOrder1)
    //     : a.sortOrder2.compareTo(b.sortOrder2));

    return newSortOrder;
  }

  static double findHighestSortOrder<T extends Sortable2>(
    List<T> items,
    SortOrderType sortOrderType,
  ) {
    if (items.isEmpty) {
      return 0;
    }

    if (sortOrderType == SortOrderType.sortOrder1) {
      return items.reduce((a, b) => a.sortOrder1 > b.sortOrder1 ? a : b).sortOrder1;
    }

    return items.reduce((a, b) => a.sortOrder2 > b.sortOrder2 ? a : b).sortOrder2;
  }

  static double findLowestSortOrder<T extends Sortable2>(
    List<T> items,
    SortOrderType sortOrderType,
  ) {
    if (items.isEmpty) {
      return 0;
    }

    if (sortOrderType == SortOrderType.sortOrder1) {
      return items.reduce((a, b) => a.sortOrder1 < b.sortOrder1 ? a : b).sortOrder1;
    }

    return items.reduce((a, b) => a.sortOrder2 < b.sortOrder2 ? a : b).sortOrder2;
  }
}
