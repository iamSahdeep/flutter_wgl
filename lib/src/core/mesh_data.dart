part of core;

Float32List FlattenVector3List(List<VM.Vector3> v, [Float32List data]) {
  if (data == null) data = Float32List(v.length * 3);
  for (int i = 0; i < v.length; ++i) {
    data[i * 3 + 0] = v[i].x;
    data[i * 3 + 1] = v[i].y;
    data[i * 3 + 2] = v[i].z;
  }
  return data;
}

Float32List FlattenVector2List(List<VM.Vector2> v, [Float32List data]) {
  if (data == null) data = Float32List(v.length * 2);
  for (int i = 0; i < v.length; ++i) {
    data[i * 2 + 0] = v[i].x;
    data[i * 2 + 1] = v[i].y;
  }
  return data;
}

Float32List FlattenVector4List(List<VM.Vector4> v, [Float32List data]) {
  if (data == null) data = Float32List(v.length * 4);
  for (int i = 0; i < v.length; ++i) {
    data[i * 4 + 0] = v[i].x;
    data[i * 4 + 1] = v[i].y;
    data[i * 4 + 2] = v[i].z;
    data[i * 4 + 3] = v[i].w;
  }
  return data;
}

Uint32List FlattenUvec4List(List<List<int>> v, [Uint32List data]) {
  if (data == null) data = Uint32List(v.length * 4);
  for (int i = 0; i < v.length; ++i) {
    data[i * 4 + 0] = v[i][0];
    data[i * 4 + 1] = v[i][1];
    data[i * 4 + 2] = v[i][2];
    data[i * 4 + 3] = v[i][3];
  }
  return data;
}

Float32List FlattenMatrix4List(List<VM.Matrix4> v, [Float32List data]) {
  if (data == null) data = Float32List(v.length * 16);
  for (int i = 0; i < v.length; ++i) {
    VM.Matrix4 m = v[i];
    for (int j = 0; j < 16; ++j) data[i * 16 + j] = m[j];
  }
  return data;
}

/// represent the raw data for mesh.
/// Internally this is wrapper around a Vertex Array Object (VAO).
/// MeshData objects can be populated directly but often they
/// will derived from **GeometryBuilder** objects.
/// The other common way to create a MeshData object is via
/// RenderProgram.MakeMeshData().
/// Note, MeshData is always associated with a specific RenderProgram
/// but it is possible to assert compatibility with multiple RenderPrograms.
class MeshData extends NamedEntity {
  MeshData(String name, this._cgl, this._drawMode, this._locationMap)
      : _vao = _cgl.createVertexArray(),
        super("meshdata:" + name);

  final FlutterWGL _cgl;
  final Object _vao;
  final int _drawMode;
  final Map<String, Object /* gl Buffer */ > _buffers = {};
  final Map<String, int> _locationMap;
  Object /* gl Buffer */ _indexBuffer;
  int _instances = 0;
  int _indexBufferType = -1;

  Float32List _vertices;
  List<int> _faces;
  Map<String, Float32List> _attributes = {};

  void clearData() {
    for (String canonical in _buffers.keys) {
      _cgl.deleteBuffer(_buffers[canonical]);
    }
    if (_indexBuffer != null) {
      _cgl.deleteBuffer(_indexBuffer);
    }
  }

  void ChangeAttribute(String canonical, List data, int width) {
    if (debug) print("ChangeBuffer ${canonical} ${data.length}");
    if (canonical.codeUnitAt(0) == prefixInstancer) {
      assert(
          data.length ~/ width == _instances, "ChangeAttribute ${_instances}");
    } else {
      assert(data.length ~/ width == _vertices.length ~/ 3,
          "wrong size for attribute: ${canonical} expected: ${_vertices.length ~/ 3} got: ${data.length ~/ width}");
    }
    _attributes[canonical] = data;
    _cgl.ChangeArrayBuffer(_buffers[canonical], data);
  }

  void ChangeVertices(Float32List data) {
    final String canonical = aPosition;
    _vertices = data;
    ChangeAttribute(canonical, data, 3);
  }

  bool SupportsAttribute(String canonical) {
    return _locationMap.containsKey(canonical);
  }

  int get drawMode => _drawMode;

  int get elementArrayBufferType => _indexBufferType;

  int GetNumItems() {
    if (_faces != null) {
      return _faces.length;
    }
    return _vertices.length ~/ 3;
  }

  int GetNumInstances() {
    return _instances;
  }

  Float32List GetAttribute(String canonical) {
    return _attributes[canonical];
  }

  dynamic GetBuffer(String canonical) {
    return _buffers[canonical];
  }

  void AddAttribute(String canonical, List data, int width) {
    final bool instanced = canonical.codeUnitAt(0) == prefixInstancer;
    if (instanced && _instances == 0) {
      _instances = data.length ~/ width;
    }
    _buffers[canonical] = _cgl.createBuffer();
    ChangeAttribute(canonical, data, width);
    ShaderVarDesc desc = RetrieveShaderVarDesc(canonical);
    if (desc == null) throw "Unknown canonical ${canonical}";
    assert(_locationMap.containsKey(canonical),
        "unexpected attribute ${canonical}");

    final int index = _locationMap[canonical];
    _cgl.bindVertexArray(_vao);
    _cgl.enableVertexAttribArray(index, instanced ? 1 : 0);
    _cgl.vertexAttribPointer(
        _buffers[canonical], index, desc.GetSize(), GL_FLOAT, false, 0, 0);
  }

  void AddVertices(Float32List data) {
    final String canonical = aPosition;
    _buffers[canonical] = _cgl.createBuffer();
    ChangeVertices(data);
    ShaderVarDesc desc = RetrieveShaderVarDesc(canonical);
    if (desc == null) throw "Unknown canonical ${canonical}";
    assert(_locationMap.containsKey(canonical));
    int index = _locationMap[canonical];
    _cgl.bindVertexArray(_vao);
    _cgl.enableVertexAttribArray(index, 0);
    _cgl.vertexAttribPointer(
        _buffers[canonical], index, desc.GetSize(), GL_FLOAT, false, 0, 0);
  }

  void ChangeFaces(List<int> faces) {
    assert(_vertices != null);
    if (_vertices.length < 3 * 256) {
      _faces = Uint8List.fromList(faces);
      _indexBufferType = GL_UNSIGNED_BYTE;
    } else if (_vertices.length < 3 * 65536) {
      _faces = Uint16List.fromList(faces);
      _indexBufferType = GL_UNSIGNED_SHORT;
    } else {
      _faces = Uint32List.fromList(faces);
      _indexBufferType = GL_UNSIGNED_INT;
    }

    _cgl.bindVertexArray(_vao);
    _cgl.ChangeElementArrayBuffer(_indexBuffer, _faces as TypedData);
  }

  void AddFaces(List<int> faces) {
    _indexBuffer = _cgl.createBuffer();
    ChangeFaces(faces);
  }

  void Activate() {
    _cgl.bindVertexArray(_vao);
  }

  Iterable<String> GetAttributes() {
    return _attributes.keys;
  }

  @override
  String toString() {
    int nf = _faces == null ? 0 : _faces.length;
    List<String> lst = ["Faces:${nf}"];
    for (String c in _attributes.keys) {
      lst.add("${c}:${_attributes[c].length}");
    }

    return "MESH[${name}] " + lst.join("  ");
  }
}

void _GeometryBuilderAttributesToMeshData(GeometryBuilder gb, MeshData md) {
  for (String canonical in gb.attributes.keys) {
    if (!md.SupportsAttribute(canonical)) {
      LogInfo("Dropping unnecessary attribute: ${canonical}");
      continue;
    }
    List lst = gb.attributes[canonical];
    ShaderVarDesc desc = RetrieveShaderVarDesc(canonical);

    //print("${md.name} ${canonical} ${lst}");
    switch (desc.type) {
      case VarTypeVec2:
        md.AddAttribute(
            canonical, FlattenVector2List(lst as List<VM.Vector2>), 2);
        break;
      case VarTypeVec3:
        md.AddAttribute(
            canonical, FlattenVector3List(lst as List<VM.Vector3>), 3);
        break;
      case VarTypeVec4:
        md.AddAttribute(
            canonical, FlattenVector4List(lst as List<VM.Vector4>), 4);
        break;
      case VarTypeFloat:
        md.AddAttribute(
            canonical, Float32List.fromList(lst as List<double>), 1);
        break;
      case VarTypeUvec4:
        md.AddAttribute(canonical, FlattenUvec4List(lst as List<List<int>>), 4);
        break;
      default:
        assert(false,
            "unknown type for ${canonical} [${lst[0].runtimeType}] [${lst.runtimeType}] ${lst}");
    }
  }
}

MeshData GeometryBuilderToMeshData(
    String name, RenderProgram prog, GeometryBuilder gb) {
  MeshData md =
      prog.MakeMeshData(name, gb.pointsOnly ? GL_POINTS : GL_TRIANGLES);
  md.AddVertices(FlattenVector3List(gb.vertices));
  if (!gb.pointsOnly) md.AddFaces(gb.GenerateFaceIndices());
  _GeometryBuilderAttributesToMeshData(gb, md);
  return md;
}

MeshData _ExtractWireframeNormals(
    MeshData out, List<double> vertices, List<double> normals, double scale) {
  assert(vertices.length == normals.length);
  Float32List v = Float32List(2 * vertices.length);
  for (int i = 0; i < vertices.length; i += 3) {
    v[2 * i + 0] = vertices[i + 0];
    v[2 * i + 1] = vertices[i + 1];
    v[2 * i + 2] = vertices[i + 2];
    v[2 * i + 3] = vertices[i + 0] + scale * normals[i + 0];
    v[2 * i + 4] = vertices[i + 1] + scale * normals[i + 1];
    v[2 * i + 5] = vertices[i + 2] + scale * normals[i + 2];
  }
  out.AddVertices(v);

  final int n = 2 * vertices.length ~/ 3;
  List<int> lines = List<int>(n);
  for (int i = 0; i < n; i++) {
    lines[i] = i;
  }

  out.AddFaces(lines);
  return out;
}

MeshData GeometryBuilderToWireframeNormals(
    RenderProgram prog, GeometryBuilder gb,
    [double scale = 1.0]) {
  MeshData out = prog.MakeMeshData("norm", GL_LINES);
  return _ExtractWireframeNormals(out, FlattenVector3List(gb.vertices),
      FlattenVector3List(gb.attributes[aNormal] as List<VM.Vector3>), scale);
}

//Extract Wireframe MeshData
MeshData GeometryBuilderToMeshDataWireframe(
    String name, RenderProgram prog, GeometryBuilder gb) {
  MeshData md = prog.MakeMeshData(name, GL_LINES);
  md.AddVertices(FlattenVector3List(gb.vertices));
  md.AddFaces(gb.GenerateLineIndices());
  _GeometryBuilderAttributesToMeshData(gb, md);
  return md;
}

MeshData LineEndPointsToMeshData(
    String name, RenderProgram prog, List<VM.Vector3> points) {
  MeshData md = prog.MakeMeshData(name, GL_LINES);
  md.AddVertices(FlattenVector3List(points));
  List<int> faces = List<int>(points.length);
  for (int i = 0; i < points.length; ++i) faces[i] = i;
  md.AddFaces(faces);
  return md;
}

MeshData ExtractWireframeNormals(RenderProgram prog, MeshData md,
    [double scale = 1.0]) {
  assert(md._drawMode == GL_TRIANGLES, "expected GL_TRIANGLES");
  MeshData out = prog.MakeMeshData(md.name, GL_LINES);
  final Float32List vertices = md.GetAttribute(aPosition);
  final Float32List normals = md.GetAttribute(aNormal);
  return _ExtractWireframeNormals(out, vertices, normals, scale);
}

MeshData ExtractWireframe(RenderProgram prog, MeshData md) {
  assert(md._drawMode == GL_TRIANGLES);
  MeshData out = prog.MakeMeshData(md.name, GL_LINES);
  out.AddVertices(md._vertices);
  final List<int> faces = md._faces;
  List<int> lines = List<int>(faces.length * 2);
  for (int i = 0; i < faces.length; i += 3) {
    lines[i * 2 + 0] = faces[i + 0];
    lines[i * 2 + 1] = faces[i + 1];
    lines[i * 2 + 2] = faces[i + 1];
    lines[i * 2 + 3] = faces[i + 2];
    lines[i * 2 + 4] = faces[i + 2];
    lines[i * 2 + 5] = faces[i + 0];
  }

  out.AddFaces(lines);
  return out;
}

MeshData ExtractPointCloud(RenderProgram prog, MeshData md) {
  assert(md._drawMode == GL_TRIANGLES, "expected GL_TRIANGLES");
  assert(md.SupportsAttribute(aNormal), "expected support for aNormal");
  MeshData out = prog.MakeMeshData(md.name, GL_POINTS);
  out.AddVertices(md._vertices);
  out.AddAttribute(aNormal, md.GetAttribute(aNormal), 3);
  return out;
}
