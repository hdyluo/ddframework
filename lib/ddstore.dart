library ddstore;

/// Provider 只能提供事件驱动，而且只能驱动一种事件。但是如果想监听的话却很不方便
/// DDStore 1.多事件，2.提供事件驱动和事件监听  2. 非驱动型数据存储和获取

import 'package:flutter/material.dart';

/// Store 保留Action  当数据变更的时候，通知修改
const _onValuesChangedAction = '_onValuesChanged';

/// 监听者
class DDListener {
  final String name;
  final Function(dynamic obj) action;
  final dynamic listener;
  DDListener(
      {required this.name, required this.action, required this.listener});
}

/// 事件派发的模型
class DDValue<T> {
  final T oldVal;
  final T newVal;
  final String key;

  DDValue({required this.oldVal, required this.newVal, required this.key});
}

class DDStore {
  final String? desc;
  DDStore({this.desc}) {
    if (desc != null) {
      print(">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>$desc 创建成功");
    }
  }

  /// 当前上下文中的数据[在处理无关widget状态共享数据的时候特别方便,当然在处理父子数据之间状态也可以]
  Map<String, dynamic> _values = {};

  /// 当前上下文中更新数据[有数据更新的时候回触发一个事件，所有监听的对象都可以收到数据更新的事件]
  void _update(String key, bool needListen, dynamic obj) {
    DDValue value = DDValue(key: key, oldVal: _values[key], newVal: obj);
    if (needListen) {
      _dispatch("${_onValuesChangedAction}_$key", value);
    }
    if (obj == null) {
      _values.remove(key);
    }
    _values[key] = obj;
  }

  /// 获取当前上下文中的数据
  dynamic _getValue(String key) {
    return _values[key];
  }

  /// [事件驱动型，在处理复杂层级关系widget之间通信上特别方便]
  Map<String, List<DDListener>> _listener = {};
  void _addListener(
      dynamic listener, String name, void Function(dynamic) action) {
    List<DDListener>? item = _listener[name];
    if (item == null) {
      item = [];
    }
    final DDListener aListener =
        DDListener(name: name, action: action, listener: listener);
    for (var i = 0; i < item.length; i++) {
      if (item[i].listener == listener) {
        print("对同一个对象重复添加相同的监听者会覆盖原监听者:$name");
        item[i] = aListener;
        return;
      }
    }
    item.add(aListener);
    _listener[name] = item;
  }

  void _removeListener(dynamic listener, {String? name}) {
    // 移除当前监听者下的所有事件
    if (name == null) {
      var emptyNames = [];
      _listener.forEach((key, value) {
        value.removeWhere((element) {
          return element.listener == null || element.listener == listener;
        });
        if (value.length == 0) {
          emptyNames.add(key);
        }
      });
      emptyNames.forEach((element) {
        _listener.remove(element);
      });
      return;
    }

    var items = _listener[name];
    if (items == null) {
      return;
    }
    items.removeWhere((item) {
      var currentListener = item.listener;
      if (currentListener == null) {
        return true;
      }
      if (listener == currentListener) {
        return true;
      }
      return false;
    });
    if (items.length == 0) {
      _listener.remove(name);
    }
  }

  void _dispatch(String name, dynamic data) {
    print("<<<<<<<<<<<<<<<<<<<<<派发事件：$name");
    var items = _listener[name];
    if (items == null) {
      return;
    }
    items.forEach((item) {
      final listener = item.listener;
      if (listener == null) {
        return;
      }
      final action = item.action;
      if (action is Function(dynamic)) {
        action(data);
      }
    });
  }

  void dispose() {
    _values = {};
    _listener = {};
  }
}

/// Store代理，目的是为了隐藏内部细节，不能在外部做dispose[在设计模式上叫做代理模式！]
class DDStoreAgent {
  DDStore? _store;
  DDStoreAgent({DDStore? store}) {
    _store = store;
  }

  void addListener(
      {@required dynamic listener,
      required String name,
      required void Function(dynamic) action}) {
    _store?._addListener(listener, name, action);
  }

  void removeListener(dynamic listener, {String? name}) {
    _store?._removeListener(listener, name: name);
  }

  void update(
      {required String key, bool needListen = false, @required dynamic value}) {
    _store?._update(key, needListen, value);
  }

  dynamic getValue(String key) {
    return _store?._getValue(key);
  }

  void dispatch({required String name, dynamic data}) {
    _store?._dispatch(name, data);
  }
}

abstract class DDStoreState<T extends StatefulWidget> extends State {
  DDStoreAgent? _storeAgent;
  DDStoreAgent? get storeAgent {
    return _storeAgent;
  }

  bool _isRootStore = false;
  bool get isRootStore {
    return _isRootStore;
  }

  @override
  T get widget {
    return super.widget as T;
  }

  @override
  void initState() {
    super.initState();
    if (forceRootStore()) {
      _isRootStore = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initStore();
  }

  @override
  void dispose() {
    if (_isRootStore) {
      _storeAgent?._store?.dispose();
      _storeAgent?._store = null;
    } else {
      _storeAgent?.removeListener(this);
    }
    super.dispose();
  }

  void _initStore() {
    if (_storeAgent != null) {
      return;
    }
    _storeAgent = DDStoreAgent();
    if (forceRootStore()) {
      _isRootStore = true;
      _storeAgent?._store = DDStore();
    } else {
      final state = context.findAncestorStateOfType<DDStoreState>();
      if (state != null) {
        if (state._storeAgent != null) {
          _storeAgent?._store = state._storeAgent?._store;
        }
      }
      if (_storeAgent?._store == null) {
        _isRootStore = true;
        _storeAgent?._store = DDStore();
      }
    }
    final prop = props();
    if (prop != null) {
      prop.forEach((key, value) {
        _storeAgent?.addListener(
            listener: this,
            name: "${_onValuesChangedAction}_$key",
            action: value);
      });
    }
    onStoreCreated();
  }

  /// 在这里做事件的监听
  @protected
  void onStoreCreated();

  /// 在这里做值变化的监听
  @protected
  Map<String, void Function(dynamic val)>? props() {
    return null;
  }

  /// 是否强制它为root[tabbar下的几个视图，需要强制为rootStore]
  @protected
  bool forceRootStore() {
    return false;
  }
}
