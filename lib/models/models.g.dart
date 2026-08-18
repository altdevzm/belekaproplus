// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetUserCollection on Isar {
  IsarCollection<User> get users => this.collection();
}

const UserSchema = CollectionSchema(
  name: r'User',
  id: -7838171048429979076,
  properties: {
    r'isActive': PropertySchema(
      id: 0,
      name: r'isActive',
      type: IsarType.bool,
    ),
    r'name': PropertySchema(
      id: 1,
      name: r'name',
      type: IsarType.string,
    ),
    r'numericId': PropertySchema(
      id: 2,
      name: r'numericId',
      type: IsarType.string,
    ),
    r'passwordHash': PropertySchema(
      id: 3,
      name: r'passwordHash',
      type: IsarType.string,
    ),
    r'role': PropertySchema(
      id: 4,
      name: r'role',
      type: IsarType.string,
    )
  },
  estimateSize: _userEstimateSize,
  serialize: _userSerialize,
  deserialize: _userDeserialize,
  deserializeProp: _userDeserializeProp,
  idName: r'id',
  indexes: {
    r'numericId': IndexSchema(
      id: -5483181632855713718,
      name: r'numericId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'numericId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'isActive': IndexSchema(
      id: 8092228061260947457,
      name: r'isActive',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'isActive',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _userGetId,
  getLinks: _userGetLinks,
  attach: _userAttach,
  version: '3.1.0+1',
);

int _userEstimateSize(
  User object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.name.length * 3;
  bytesCount += 3 + object.numericId.length * 3;
  bytesCount += 3 + object.passwordHash.length * 3;
  bytesCount += 3 + object.role.length * 3;
  return bytesCount;
}

void _userSerialize(
  User object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeBool(offsets[0], object.isActive);
  writer.writeString(offsets[1], object.name);
  writer.writeString(offsets[2], object.numericId);
  writer.writeString(offsets[3], object.passwordHash);
  writer.writeString(offsets[4], object.role);
}

User _userDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = User();
  object.id = id;
  object.isActive = reader.readBool(offsets[0]);
  object.name = reader.readString(offsets[1]);
  object.numericId = reader.readString(offsets[2]);
  object.passwordHash = reader.readString(offsets[3]);
  object.role = reader.readString(offsets[4]);
  return object;
}

P _userDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readBool(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _userGetId(User object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _userGetLinks(User object) {
  return [];
}

void _userAttach(IsarCollection<dynamic> col, Id id, User object) {
  object.id = id;
}

extension UserByIndex on IsarCollection<User> {
  Future<User?> getByNumericId(String numericId) {
    return getByIndex(r'numericId', [numericId]);
  }

  User? getByNumericIdSync(String numericId) {
    return getByIndexSync(r'numericId', [numericId]);
  }

  Future<bool> deleteByNumericId(String numericId) {
    return deleteByIndex(r'numericId', [numericId]);
  }

  bool deleteByNumericIdSync(String numericId) {
    return deleteByIndexSync(r'numericId', [numericId]);
  }

  Future<List<User?>> getAllByNumericId(List<String> numericIdValues) {
    final values = numericIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'numericId', values);
  }

  List<User?> getAllByNumericIdSync(List<String> numericIdValues) {
    final values = numericIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'numericId', values);
  }

  Future<int> deleteAllByNumericId(List<String> numericIdValues) {
    final values = numericIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'numericId', values);
  }

  int deleteAllByNumericIdSync(List<String> numericIdValues) {
    final values = numericIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'numericId', values);
  }

  Future<Id> putByNumericId(User object) {
    return putByIndex(r'numericId', object);
  }

  Id putByNumericIdSync(User object, {bool saveLinks = true}) {
    return putByIndexSync(r'numericId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByNumericId(List<User> objects) {
    return putAllByIndex(r'numericId', objects);
  }

  List<Id> putAllByNumericIdSync(List<User> objects, {bool saveLinks = true}) {
    return putAllByIndexSync(r'numericId', objects, saveLinks: saveLinks);
  }
}

extension UserQueryWhereSort on QueryBuilder<User, User, QWhere> {
  QueryBuilder<User, User, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<User, User, QAfterWhere> anyIsActive() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'isActive'),
      );
    });
  }
}

extension UserQueryWhere on QueryBuilder<User, User, QWhereClause> {
  QueryBuilder<User, User, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<User, User, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<User, User, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<User, User, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<User, User, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<User, User, QAfterWhereClause> numericIdEqualTo(
      String numericId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'numericId',
        value: [numericId],
      ));
    });
  }

  QueryBuilder<User, User, QAfterWhereClause> numericIdNotEqualTo(
      String numericId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'numericId',
              lower: [],
              upper: [numericId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'numericId',
              lower: [numericId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'numericId',
              lower: [numericId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'numericId',
              lower: [],
              upper: [numericId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<User, User, QAfterWhereClause> isActiveEqualTo(bool isActive) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'isActive',
        value: [isActive],
      ));
    });
  }

  QueryBuilder<User, User, QAfterWhereClause> isActiveNotEqualTo(
      bool isActive) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isActive',
              lower: [],
              upper: [isActive],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isActive',
              lower: [isActive],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isActive',
              lower: [isActive],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isActive',
              lower: [],
              upper: [isActive],
              includeUpper: false,
            ));
      }
    });
  }
}

extension UserQueryFilter on QueryBuilder<User, User, QFilterCondition> {
  QueryBuilder<User, User, QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> isActiveEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isActive',
        value: value,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'name',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> nameContains(String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> nameMatches(String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> numericIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'numericId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> numericIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'numericId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> numericIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'numericId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> numericIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'numericId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> numericIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'numericId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> numericIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'numericId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> numericIdContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'numericId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> numericIdMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'numericId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> numericIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'numericId',
        value: '',
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> numericIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'numericId',
        value: '',
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> passwordHashEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'passwordHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> passwordHashGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'passwordHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> passwordHashLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'passwordHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> passwordHashBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'passwordHash',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> passwordHashStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'passwordHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> passwordHashEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'passwordHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> passwordHashContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'passwordHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> passwordHashMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'passwordHash',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> passwordHashIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'passwordHash',
        value: '',
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> passwordHashIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'passwordHash',
        value: '',
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> roleEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'role',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> roleGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'role',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> roleLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'role',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> roleBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'role',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> roleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'role',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> roleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'role',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> roleContains(String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'role',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> roleMatches(String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'role',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> roleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'role',
        value: '',
      ));
    });
  }

  QueryBuilder<User, User, QAfterFilterCondition> roleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'role',
        value: '',
      ));
    });
  }
}

extension UserQueryObject on QueryBuilder<User, User, QFilterCondition> {}

extension UserQueryLinks on QueryBuilder<User, User, QFilterCondition> {}

extension UserQuerySortBy on QueryBuilder<User, User, QSortBy> {
  QueryBuilder<User, User, QAfterSortBy> sortByIsActive() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isActive', Sort.asc);
    });
  }

  QueryBuilder<User, User, QAfterSortBy> sortByIsActiveDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isActive', Sort.desc);
    });
  }

  QueryBuilder<User, User, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<User, User, QAfterSortBy> sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<User, User, QAfterSortBy> sortByNumericId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'numericId', Sort.asc);
    });
  }

  QueryBuilder<User, User, QAfterSortBy> sortByNumericIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'numericId', Sort.desc);
    });
  }

  QueryBuilder<User, User, QAfterSortBy> sortByPasswordHash() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'passwordHash', Sort.asc);
    });
  }

  QueryBuilder<User, User, QAfterSortBy> sortByPasswordHashDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'passwordHash', Sort.desc);
    });
  }

  QueryBuilder<User, User, QAfterSortBy> sortByRole() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'role', Sort.asc);
    });
  }

  QueryBuilder<User, User, QAfterSortBy> sortByRoleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'role', Sort.desc);
    });
  }
}

extension UserQuerySortThenBy on QueryBuilder<User, User, QSortThenBy> {
  QueryBuilder<User, User, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<User, User, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<User, User, QAfterSortBy> thenByIsActive() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isActive', Sort.asc);
    });
  }

  QueryBuilder<User, User, QAfterSortBy> thenByIsActiveDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isActive', Sort.desc);
    });
  }

  QueryBuilder<User, User, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<User, User, QAfterSortBy> thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<User, User, QAfterSortBy> thenByNumericId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'numericId', Sort.asc);
    });
  }

  QueryBuilder<User, User, QAfterSortBy> thenByNumericIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'numericId', Sort.desc);
    });
  }

  QueryBuilder<User, User, QAfterSortBy> thenByPasswordHash() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'passwordHash', Sort.asc);
    });
  }

  QueryBuilder<User, User, QAfterSortBy> thenByPasswordHashDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'passwordHash', Sort.desc);
    });
  }

  QueryBuilder<User, User, QAfterSortBy> thenByRole() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'role', Sort.asc);
    });
  }

  QueryBuilder<User, User, QAfterSortBy> thenByRoleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'role', Sort.desc);
    });
  }
}

extension UserQueryWhereDistinct on QueryBuilder<User, User, QDistinct> {
  QueryBuilder<User, User, QDistinct> distinctByIsActive() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isActive');
    });
  }

  QueryBuilder<User, User, QDistinct> distinctByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<User, User, QDistinct> distinctByNumericId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'numericId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<User, User, QDistinct> distinctByPasswordHash(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'passwordHash', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<User, User, QDistinct> distinctByRole(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'role', caseSensitive: caseSensitive);
    });
  }
}

extension UserQueryProperty on QueryBuilder<User, User, QQueryProperty> {
  QueryBuilder<User, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<User, bool, QQueryOperations> isActiveProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isActive');
    });
  }

  QueryBuilder<User, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<User, String, QQueryOperations> numericIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'numericId');
    });
  }

  QueryBuilder<User, String, QQueryOperations> passwordHashProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'passwordHash');
    });
  }

  QueryBuilder<User, String, QQueryOperations> roleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'role');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetCategoryCollection on Isar {
  IsarCollection<Category> get categorys => this.collection();
}

const CategorySchema = CollectionSchema(
  name: r'Category',
  id: 5751694338128944171,
  properties: {
    r'iconPath': PropertySchema(
      id: 0,
      name: r'iconPath',
      type: IsarType.string,
    ),
    r'name': PropertySchema(
      id: 1,
      name: r'name',
      type: IsarType.string,
    ),
    r'sector': PropertySchema(
      id: 2,
      name: r'sector',
      type: IsarType.byte,
      enumMap: _CategorysectorEnumValueMap,
    )
  },
  estimateSize: _categoryEstimateSize,
  serialize: _categorySerialize,
  deserialize: _categoryDeserialize,
  deserializeProp: _categoryDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _categoryGetId,
  getLinks: _categoryGetLinks,
  attach: _categoryAttach,
  version: '3.1.0+1',
);

int _categoryEstimateSize(
  Category object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.iconPath.length * 3;
  bytesCount += 3 + object.name.length * 3;
  return bytesCount;
}

void _categorySerialize(
  Category object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.iconPath);
  writer.writeString(offsets[1], object.name);
  writer.writeByte(offsets[2], object.sector.index);
}

Category _categoryDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = Category(
    iconPath: reader.readStringOrNull(offsets[0]) ?? '',
    name: reader.readString(offsets[1]),
    sector: _CategorysectorValueEnumMap[reader.readByteOrNull(offsets[2])] ??
        CategorySector.other,
  );
  object.id = id;
  return object;
}

P _categoryDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset) ?? '') as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (_CategorysectorValueEnumMap[reader.readByteOrNull(offset)] ??
          CategorySector.other) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

const _CategorysectorEnumValueMap = {
  'pharmacy': 0,
  'stationery': 1,
  'grocery': 2,
  'food': 3,
  'restaurant': 4,
  'other': 5,
};
const _CategorysectorValueEnumMap = {
  0: CategorySector.pharmacy,
  1: CategorySector.stationery,
  2: CategorySector.grocery,
  3: CategorySector.food,
  4: CategorySector.restaurant,
  5: CategorySector.other,
};

Id _categoryGetId(Category object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _categoryGetLinks(Category object) {
  return [];
}

void _categoryAttach(IsarCollection<dynamic> col, Id id, Category object) {
  object.id = id;
}

extension CategoryQueryWhereSort on QueryBuilder<Category, Category, QWhere> {
  QueryBuilder<Category, Category, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension CategoryQueryWhere on QueryBuilder<Category, Category, QWhereClause> {
  QueryBuilder<Category, Category, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<Category, Category, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<Category, Category, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<Category, Category, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension CategoryQueryFilter
    on QueryBuilder<Category, Category, QFilterCondition> {
  QueryBuilder<Category, Category, QAfterFilterCondition> iconPathEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'iconPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> iconPathGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'iconPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> iconPathLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'iconPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> iconPathBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'iconPath',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> iconPathStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'iconPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> iconPathEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'iconPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> iconPathContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'iconPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> iconPathMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'iconPath',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> iconPathIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'iconPath',
        value: '',
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> iconPathIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'iconPath',
        value: '',
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'name',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> nameContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> nameMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> sectorEqualTo(
      CategorySector value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sector',
        value: value,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> sectorGreaterThan(
    CategorySector value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sector',
        value: value,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> sectorLessThan(
    CategorySector value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sector',
        value: value,
      ));
    });
  }

  QueryBuilder<Category, Category, QAfterFilterCondition> sectorBetween(
    CategorySector lower,
    CategorySector upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sector',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension CategoryQueryObject
    on QueryBuilder<Category, Category, QFilterCondition> {}

extension CategoryQueryLinks
    on QueryBuilder<Category, Category, QFilterCondition> {}

extension CategoryQuerySortBy on QueryBuilder<Category, Category, QSortBy> {
  QueryBuilder<Category, Category, QAfterSortBy> sortByIconPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'iconPath', Sort.asc);
    });
  }

  QueryBuilder<Category, Category, QAfterSortBy> sortByIconPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'iconPath', Sort.desc);
    });
  }

  QueryBuilder<Category, Category, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<Category, Category, QAfterSortBy> sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<Category, Category, QAfterSortBy> sortBySector() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sector', Sort.asc);
    });
  }

  QueryBuilder<Category, Category, QAfterSortBy> sortBySectorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sector', Sort.desc);
    });
  }
}

extension CategoryQuerySortThenBy
    on QueryBuilder<Category, Category, QSortThenBy> {
  QueryBuilder<Category, Category, QAfterSortBy> thenByIconPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'iconPath', Sort.asc);
    });
  }

  QueryBuilder<Category, Category, QAfterSortBy> thenByIconPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'iconPath', Sort.desc);
    });
  }

  QueryBuilder<Category, Category, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<Category, Category, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<Category, Category, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<Category, Category, QAfterSortBy> thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<Category, Category, QAfterSortBy> thenBySector() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sector', Sort.asc);
    });
  }

  QueryBuilder<Category, Category, QAfterSortBy> thenBySectorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sector', Sort.desc);
    });
  }
}

extension CategoryQueryWhereDistinct
    on QueryBuilder<Category, Category, QDistinct> {
  QueryBuilder<Category, Category, QDistinct> distinctByIconPath(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'iconPath', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Category, Category, QDistinct> distinctByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Category, Category, QDistinct> distinctBySector() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sector');
    });
  }
}

extension CategoryQueryProperty
    on QueryBuilder<Category, Category, QQueryProperty> {
  QueryBuilder<Category, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<Category, String, QQueryOperations> iconPathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'iconPath');
    });
  }

  QueryBuilder<Category, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<Category, CategorySector, QQueryOperations> sectorProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sector');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetProductCollection on Isar {
  IsarCollection<Product> get products => this.collection();
}

const ProductSchema = CollectionSchema(
  name: r'Product',
  id: -6222113721139403729,
  properties: {
    r'categoryId': PropertySchema(
      id: 0,
      name: r'categoryId',
      type: IsarType.long,
    ),
    r'colors': PropertySchema(
      id: 1,
      name: r'colors',
      type: IsarType.stringList,
    ),
    r'discountEndDate': PropertySchema(
      id: 2,
      name: r'discountEndDate',
      type: IsarType.dateTime,
    ),
    r'discountPrice': PropertySchema(
      id: 3,
      name: r'discountPrice',
      type: IsarType.double,
    ),
    r'discountStartDate': PropertySchema(
      id: 4,
      name: r'discountStartDate',
      type: IsarType.dateTime,
    ),
    r'imagePath': PropertySchema(
      id: 5,
      name: r'imagePath',
      type: IsarType.string,
    ),
    r'isArchived': PropertySchema(
      id: 6,
      name: r'isArchived',
      type: IsarType.bool,
    ),
    r'isTaxInclusive': PropertySchema(
      id: 7,
      name: r'isTaxInclusive',
      type: IsarType.bool,
    ),
    r'name': PropertySchema(
      id: 8,
      name: r'name',
      type: IsarType.string,
    ),
    r'price': PropertySchema(
      id: 9,
      name: r'price',
      type: IsarType.double,
    ),
    r'sizes': PropertySchema(
      id: 10,
      name: r'sizes',
      type: IsarType.stringList,
    ),
    r'sku': PropertySchema(
      id: 11,
      name: r'sku',
      type: IsarType.string,
    ),
    r'stockLevel': PropertySchema(
      id: 12,
      name: r'stockLevel',
      type: IsarType.long,
    ),
    r'taxRate': PropertySchema(
      id: 13,
      name: r'taxRate',
      type: IsarType.double,
    ),
    r'unitCost': PropertySchema(
      id: 14,
      name: r'unitCost',
      type: IsarType.double,
    )
  },
  estimateSize: _productEstimateSize,
  serialize: _productSerialize,
  deserialize: _productDeserialize,
  deserializeProp: _productDeserializeProp,
  idName: r'id',
  indexes: {
    r'sku': IndexSchema(
      id: -3348042439688860591,
      name: r'sku',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'sku',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'isArchived': IndexSchema(
      id: 655844772568347876,
      name: r'isArchived',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'isArchived',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _productGetId,
  getLinks: _productGetLinks,
  attach: _productAttach,
  version: '3.1.0+1',
);

int _productEstimateSize(
  Product object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final list = object.colors;
    if (list != null) {
      bytesCount += 3 + list.length * 3;
      {
        for (var i = 0; i < list.length; i++) {
          final value = list[i];
          bytesCount += value.length * 3;
        }
      }
    }
  }
  {
    final value = object.imagePath;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.name.length * 3;
  {
    final list = object.sizes;
    if (list != null) {
      bytesCount += 3 + list.length * 3;
      {
        for (var i = 0; i < list.length; i++) {
          final value = list[i];
          bytesCount += value.length * 3;
        }
      }
    }
  }
  bytesCount += 3 + object.sku.length * 3;
  return bytesCount;
}

void _productSerialize(
  Product object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.categoryId);
  writer.writeStringList(offsets[1], object.colors);
  writer.writeDateTime(offsets[2], object.discountEndDate);
  writer.writeDouble(offsets[3], object.discountPrice);
  writer.writeDateTime(offsets[4], object.discountStartDate);
  writer.writeString(offsets[5], object.imagePath);
  writer.writeBool(offsets[6], object.isArchived);
  writer.writeBool(offsets[7], object.isTaxInclusive);
  writer.writeString(offsets[8], object.name);
  writer.writeDouble(offsets[9], object.price);
  writer.writeStringList(offsets[10], object.sizes);
  writer.writeString(offsets[11], object.sku);
  writer.writeLong(offsets[12], object.stockLevel);
  writer.writeDouble(offsets[13], object.taxRate);
  writer.writeDouble(offsets[14], object.unitCost);
}

Product _productDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = Product(
    categoryId: reader.readLong(offsets[0]),
    colors: reader.readStringList(offsets[1]),
    discountEndDate: reader.readDateTimeOrNull(offsets[2]),
    discountPrice: reader.readDoubleOrNull(offsets[3]),
    discountStartDate: reader.readDateTimeOrNull(offsets[4]),
    imagePath: reader.readStringOrNull(offsets[5]),
    isArchived: reader.readBoolOrNull(offsets[6]) ?? false,
    isTaxInclusive: reader.readBoolOrNull(offsets[7]) ?? true,
    name: reader.readString(offsets[8]),
    price: reader.readDouble(offsets[9]),
    sizes: reader.readStringList(offsets[10]),
    sku: reader.readString(offsets[11]),
    stockLevel: reader.readLong(offsets[12]),
    taxRate: reader.readDoubleOrNull(offsets[13]) ?? 0.0,
    unitCost: reader.readDoubleOrNull(offsets[14]) ?? 0.0,
  );
  object.id = id;
  return object;
}

P _productDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readStringList(offset)) as P;
    case 2:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 3:
      return (reader.readDoubleOrNull(offset)) as P;
    case 4:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 5:
      return (reader.readStringOrNull(offset)) as P;
    case 6:
      return (reader.readBoolOrNull(offset) ?? false) as P;
    case 7:
      return (reader.readBoolOrNull(offset) ?? true) as P;
    case 8:
      return (reader.readString(offset)) as P;
    case 9:
      return (reader.readDouble(offset)) as P;
    case 10:
      return (reader.readStringList(offset)) as P;
    case 11:
      return (reader.readString(offset)) as P;
    case 12:
      return (reader.readLong(offset)) as P;
    case 13:
      return (reader.readDoubleOrNull(offset) ?? 0.0) as P;
    case 14:
      return (reader.readDoubleOrNull(offset) ?? 0.0) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _productGetId(Product object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _productGetLinks(Product object) {
  return [];
}

void _productAttach(IsarCollection<dynamic> col, Id id, Product object) {
  object.id = id;
}

extension ProductQueryWhereSort on QueryBuilder<Product, Product, QWhere> {
  QueryBuilder<Product, Product, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<Product, Product, QAfterWhere> anyIsArchived() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'isArchived'),
      );
    });
  }
}

extension ProductQueryWhere on QueryBuilder<Product, Product, QWhereClause> {
  QueryBuilder<Product, Product, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<Product, Product, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<Product, Product, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<Product, Product, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterWhereClause> skuEqualTo(String sku) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'sku',
        value: [sku],
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterWhereClause> skuNotEqualTo(String sku) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sku',
              lower: [],
              upper: [sku],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sku',
              lower: [sku],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sku',
              lower: [sku],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sku',
              lower: [],
              upper: [sku],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<Product, Product, QAfterWhereClause> isArchivedEqualTo(
      bool isArchived) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'isArchived',
        value: [isArchived],
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterWhereClause> isArchivedNotEqualTo(
      bool isArchived) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isArchived',
              lower: [],
              upper: [isArchived],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isArchived',
              lower: [isArchived],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isArchived',
              lower: [isArchived],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isArchived',
              lower: [],
              upper: [isArchived],
              includeUpper: false,
            ));
      }
    });
  }
}

extension ProductQueryFilter
    on QueryBuilder<Product, Product, QFilterCondition> {
  QueryBuilder<Product, Product, QAfterFilterCondition> categoryIdEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'categoryId',
        value: value,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> categoryIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'categoryId',
        value: value,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> categoryIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'categoryId',
        value: value,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> categoryIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'categoryId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> colorsIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'colors',
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> colorsIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'colors',
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> colorsElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'colors',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition>
      colorsElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'colors',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> colorsElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'colors',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> colorsElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'colors',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> colorsElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'colors',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> colorsElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'colors',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> colorsElementContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'colors',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> colorsElementMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'colors',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> colorsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'colors',
        value: '',
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition>
      colorsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'colors',
        value: '',
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> colorsLengthEqualTo(
      int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'colors',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> colorsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'colors',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> colorsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'colors',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> colorsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'colors',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> colorsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'colors',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> colorsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'colors',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition>
      discountEndDateIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'discountEndDate',
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition>
      discountEndDateIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'discountEndDate',
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> discountEndDateEqualTo(
      DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'discountEndDate',
        value: value,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition>
      discountEndDateGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'discountEndDate',
        value: value,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> discountEndDateLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'discountEndDate',
        value: value,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> discountEndDateBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'discountEndDate',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> discountPriceIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'discountPrice',
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition>
      discountPriceIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'discountPrice',
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> discountPriceEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'discountPrice',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition>
      discountPriceGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'discountPrice',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> discountPriceLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'discountPrice',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> discountPriceBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'discountPrice',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition>
      discountStartDateIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'discountStartDate',
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition>
      discountStartDateIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'discountStartDate',
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition>
      discountStartDateEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'discountStartDate',
        value: value,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition>
      discountStartDateGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'discountStartDate',
        value: value,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition>
      discountStartDateLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'discountStartDate',
        value: value,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition>
      discountStartDateBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'discountStartDate',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> imagePathIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'imagePath',
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> imagePathIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'imagePath',
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> imagePathEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'imagePath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> imagePathGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'imagePath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> imagePathLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'imagePath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> imagePathBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'imagePath',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> imagePathStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'imagePath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> imagePathEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'imagePath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> imagePathContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'imagePath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> imagePathMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'imagePath',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> imagePathIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'imagePath',
        value: '',
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> imagePathIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'imagePath',
        value: '',
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> isArchivedEqualTo(
      bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isArchived',
        value: value,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> isTaxInclusiveEqualTo(
      bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isTaxInclusive',
        value: value,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'name',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> nameContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> nameMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> priceEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'price',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> priceGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'price',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> priceLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'price',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> priceBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'price',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> sizesIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'sizes',
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> sizesIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'sizes',
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> sizesElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sizes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> sizesElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sizes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> sizesElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sizes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> sizesElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sizes',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> sizesElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'sizes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> sizesElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'sizes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> sizesElementContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sizes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> sizesElementMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sizes',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> sizesElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sizes',
        value: '',
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition>
      sizesElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sizes',
        value: '',
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> sizesLengthEqualTo(
      int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sizes',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> sizesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sizes',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> sizesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sizes',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> sizesLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sizes',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> sizesLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sizes',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> sizesLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sizes',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> skuEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sku',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> skuGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sku',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> skuLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sku',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> skuBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sku',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> skuStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'sku',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> skuEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'sku',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> skuContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sku',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> skuMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sku',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> skuIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sku',
        value: '',
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> skuIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sku',
        value: '',
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> stockLevelEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'stockLevel',
        value: value,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> stockLevelGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'stockLevel',
        value: value,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> stockLevelLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'stockLevel',
        value: value,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> stockLevelBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'stockLevel',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> taxRateEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'taxRate',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> taxRateGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'taxRate',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> taxRateLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'taxRate',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> taxRateBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'taxRate',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> unitCostEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'unitCost',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> unitCostGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'unitCost',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> unitCostLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'unitCost',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Product, Product, QAfterFilterCondition> unitCostBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'unitCost',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }
}

extension ProductQueryObject
    on QueryBuilder<Product, Product, QFilterCondition> {}

extension ProductQueryLinks
    on QueryBuilder<Product, Product, QFilterCondition> {}

extension ProductQuerySortBy on QueryBuilder<Product, Product, QSortBy> {
  QueryBuilder<Product, Product, QAfterSortBy> sortByCategoryId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'categoryId', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByCategoryIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'categoryId', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByDiscountEndDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discountEndDate', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByDiscountEndDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discountEndDate', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByDiscountPrice() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discountPrice', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByDiscountPriceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discountPrice', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByDiscountStartDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discountStartDate', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByDiscountStartDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discountStartDate', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByImagePath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'imagePath', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByImagePathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'imagePath', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByIsArchived() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isArchived', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByIsArchivedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isArchived', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByIsTaxInclusive() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isTaxInclusive', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByIsTaxInclusiveDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isTaxInclusive', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByPrice() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'price', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByPriceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'price', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortBySku() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sku', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortBySkuDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sku', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByStockLevel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stockLevel', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByStockLevelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stockLevel', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByTaxRate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'taxRate', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByTaxRateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'taxRate', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByUnitCost() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'unitCost', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> sortByUnitCostDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'unitCost', Sort.desc);
    });
  }
}

extension ProductQuerySortThenBy
    on QueryBuilder<Product, Product, QSortThenBy> {
  QueryBuilder<Product, Product, QAfterSortBy> thenByCategoryId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'categoryId', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByCategoryIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'categoryId', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByDiscountEndDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discountEndDate', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByDiscountEndDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discountEndDate', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByDiscountPrice() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discountPrice', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByDiscountPriceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discountPrice', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByDiscountStartDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discountStartDate', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByDiscountStartDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discountStartDate', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByImagePath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'imagePath', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByImagePathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'imagePath', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByIsArchived() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isArchived', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByIsArchivedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isArchived', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByIsTaxInclusive() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isTaxInclusive', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByIsTaxInclusiveDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isTaxInclusive', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByPrice() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'price', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByPriceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'price', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenBySku() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sku', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenBySkuDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sku', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByStockLevel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stockLevel', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByStockLevelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stockLevel', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByTaxRate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'taxRate', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByTaxRateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'taxRate', Sort.desc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByUnitCost() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'unitCost', Sort.asc);
    });
  }

  QueryBuilder<Product, Product, QAfterSortBy> thenByUnitCostDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'unitCost', Sort.desc);
    });
  }
}

extension ProductQueryWhereDistinct
    on QueryBuilder<Product, Product, QDistinct> {
  QueryBuilder<Product, Product, QDistinct> distinctByCategoryId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'categoryId');
    });
  }

  QueryBuilder<Product, Product, QDistinct> distinctByColors() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'colors');
    });
  }

  QueryBuilder<Product, Product, QDistinct> distinctByDiscountEndDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'discountEndDate');
    });
  }

  QueryBuilder<Product, Product, QDistinct> distinctByDiscountPrice() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'discountPrice');
    });
  }

  QueryBuilder<Product, Product, QDistinct> distinctByDiscountStartDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'discountStartDate');
    });
  }

  QueryBuilder<Product, Product, QDistinct> distinctByImagePath(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'imagePath', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Product, Product, QDistinct> distinctByIsArchived() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isArchived');
    });
  }

  QueryBuilder<Product, Product, QDistinct> distinctByIsTaxInclusive() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isTaxInclusive');
    });
  }

  QueryBuilder<Product, Product, QDistinct> distinctByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Product, Product, QDistinct> distinctByPrice() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'price');
    });
  }

  QueryBuilder<Product, Product, QDistinct> distinctBySizes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sizes');
    });
  }

  QueryBuilder<Product, Product, QDistinct> distinctBySku(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sku', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Product, Product, QDistinct> distinctByStockLevel() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'stockLevel');
    });
  }

  QueryBuilder<Product, Product, QDistinct> distinctByTaxRate() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'taxRate');
    });
  }

  QueryBuilder<Product, Product, QDistinct> distinctByUnitCost() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'unitCost');
    });
  }
}

extension ProductQueryProperty
    on QueryBuilder<Product, Product, QQueryProperty> {
  QueryBuilder<Product, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<Product, int, QQueryOperations> categoryIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'categoryId');
    });
  }

  QueryBuilder<Product, List<String>?, QQueryOperations> colorsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'colors');
    });
  }

  QueryBuilder<Product, DateTime?, QQueryOperations> discountEndDateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'discountEndDate');
    });
  }

  QueryBuilder<Product, double?, QQueryOperations> discountPriceProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'discountPrice');
    });
  }

  QueryBuilder<Product, DateTime?, QQueryOperations>
      discountStartDateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'discountStartDate');
    });
  }

  QueryBuilder<Product, String?, QQueryOperations> imagePathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'imagePath');
    });
  }

  QueryBuilder<Product, bool, QQueryOperations> isArchivedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isArchived');
    });
  }

  QueryBuilder<Product, bool, QQueryOperations> isTaxInclusiveProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isTaxInclusive');
    });
  }

  QueryBuilder<Product, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<Product, double, QQueryOperations> priceProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'price');
    });
  }

  QueryBuilder<Product, List<String>?, QQueryOperations> sizesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sizes');
    });
  }

  QueryBuilder<Product, String, QQueryOperations> skuProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sku');
    });
  }

  QueryBuilder<Product, int, QQueryOperations> stockLevelProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'stockLevel');
    });
  }

  QueryBuilder<Product, double, QQueryOperations> taxRateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'taxRate');
    });
  }

  QueryBuilder<Product, double, QQueryOperations> unitCostProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'unitCost');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetSaleTransactionCollection on Isar {
  IsarCollection<SaleTransaction> get saleTransactions => this.collection();
}

const SaleTransactionSchema = CollectionSchema(
  name: r'SaleTransaction',
  id: 4604198863045431712,
  properties: {
    r'cashierId': PropertySchema(
      id: 0,
      name: r'cashierId',
      type: IsarType.string,
    ),
    r'cashierName': PropertySchema(
      id: 1,
      name: r'cashierName',
      type: IsarType.string,
    ),
    r'changeAmount': PropertySchema(
      id: 2,
      name: r'changeAmount',
      type: IsarType.double,
    ),
    r'customerId': PropertySchema(
      id: 3,
      name: r'customerId',
      type: IsarType.long,
    ),
    r'discountAmount': PropertySchema(
      id: 4,
      name: r'discountAmount',
      type: IsarType.double,
    ),
    r'grossProfit': PropertySchema(
      id: 5,
      name: r'grossProfit',
      type: IsarType.double,
    ),
    r'isSynced': PropertySchema(
      id: 6,
      name: r'isSynced',
      type: IsarType.bool,
    ),
    r'paymentMethod': PropertySchema(
      id: 7,
      name: r'paymentMethod',
      type: IsarType.string,
    ),
    r'pointsEarned': PropertySchema(
      id: 8,
      name: r'pointsEarned',
      type: IsarType.long,
    ),
    r'pointsRedeemed': PropertySchema(
      id: 9,
      name: r'pointsRedeemed',
      type: IsarType.long,
    ),
    r'status': PropertySchema(
      id: 10,
      name: r'status',
      type: IsarType.string,
    ),
    r'subtotal': PropertySchema(
      id: 11,
      name: r'subtotal',
      type: IsarType.double,
    ),
    r'taxAmount': PropertySchema(
      id: 12,
      name: r'taxAmount',
      type: IsarType.double,
    ),
    r'tenderedAmount': PropertySchema(
      id: 13,
      name: r'tenderedAmount',
      type: IsarType.double,
    ),
    r'terminalName': PropertySchema(
      id: 14,
      name: r'terminalName',
      type: IsarType.string,
    ),
    r'timestamp': PropertySchema(
      id: 15,
      name: r'timestamp',
      type: IsarType.dateTime,
    ),
    r'totalAmount': PropertySchema(
      id: 16,
      name: r'totalAmount',
      type: IsarType.double,
    ),
    r'totalCost': PropertySchema(
      id: 17,
      name: r'totalCost',
      type: IsarType.double,
    ),
    r'transactionId': PropertySchema(
      id: 18,
      name: r'transactionId',
      type: IsarType.string,
    )
  },
  estimateSize: _saleTransactionEstimateSize,
  serialize: _saleTransactionSerialize,
  deserialize: _saleTransactionDeserialize,
  deserializeProp: _saleTransactionDeserializeProp,
  idName: r'id',
  indexes: {
    r'timestamp': IndexSchema(
      id: 1852253767416892198,
      name: r'timestamp',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'timestamp',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    ),
    r'transactionId': IndexSchema(
      id: 8561542235958051982,
      name: r'transactionId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'transactionId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {
    r'items': LinkSchema(
      id: -4681169290980323419,
      name: r'items',
      target: r'SaleItem',
      single: false,
    )
  },
  embeddedSchemas: {},
  getId: _saleTransactionGetId,
  getLinks: _saleTransactionGetLinks,
  attach: _saleTransactionAttach,
  version: '3.1.0+1',
);

int _saleTransactionEstimateSize(
  SaleTransaction object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.cashierId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.cashierName.length * 3;
  bytesCount += 3 + object.paymentMethod.length * 3;
  bytesCount += 3 + object.status.length * 3;
  {
    final value = object.terminalName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.transactionId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _saleTransactionSerialize(
  SaleTransaction object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.cashierId);
  writer.writeString(offsets[1], object.cashierName);
  writer.writeDouble(offsets[2], object.changeAmount);
  writer.writeLong(offsets[3], object.customerId);
  writer.writeDouble(offsets[4], object.discountAmount);
  writer.writeDouble(offsets[5], object.grossProfit);
  writer.writeBool(offsets[6], object.isSynced);
  writer.writeString(offsets[7], object.paymentMethod);
  writer.writeLong(offsets[8], object.pointsEarned);
  writer.writeLong(offsets[9], object.pointsRedeemed);
  writer.writeString(offsets[10], object.status);
  writer.writeDouble(offsets[11], object.subtotal);
  writer.writeDouble(offsets[12], object.taxAmount);
  writer.writeDouble(offsets[13], object.tenderedAmount);
  writer.writeString(offsets[14], object.terminalName);
  writer.writeDateTime(offsets[15], object.timestamp);
  writer.writeDouble(offsets[16], object.totalAmount);
  writer.writeDouble(offsets[17], object.totalCost);
  writer.writeString(offsets[18], object.transactionId);
}

SaleTransaction _saleTransactionDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = SaleTransaction(
    cashierId: reader.readStringOrNull(offsets[0]),
    cashierName: reader.readStringOrNull(offsets[1]) ?? '',
    changeAmount: reader.readDoubleOrNull(offsets[2]) ?? 0.0,
    customerId: reader.readLongOrNull(offsets[3]),
    discountAmount: reader.readDoubleOrNull(offsets[4]) ?? 0.0,
    grossProfit: reader.readDoubleOrNull(offsets[5]) ?? 0.0,
    isSynced: reader.readBoolOrNull(offsets[6]) ?? false,
    paymentMethod: reader.readString(offsets[7]),
    pointsEarned: reader.readLongOrNull(offsets[8]) ?? 0,
    pointsRedeemed: reader.readLongOrNull(offsets[9]) ?? 0,
    status: reader.readStringOrNull(offsets[10]) ?? 'completed',
    subtotal: reader.readDoubleOrNull(offsets[11]) ?? 0.0,
    taxAmount: reader.readDoubleOrNull(offsets[12]) ?? 0.0,
    tenderedAmount: reader.readDoubleOrNull(offsets[13]) ?? 0.0,
    terminalName: reader.readStringOrNull(offsets[14]),
    totalAmount: reader.readDouble(offsets[16]),
    totalCost: reader.readDoubleOrNull(offsets[17]) ?? 0.0,
    transactionId: reader.readStringOrNull(offsets[18]),
  );
  object.id = id;
  object.timestamp = reader.readDateTime(offsets[15]);
  return object;
}

P _saleTransactionDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (reader.readStringOrNull(offset) ?? '') as P;
    case 2:
      return (reader.readDoubleOrNull(offset) ?? 0.0) as P;
    case 3:
      return (reader.readLongOrNull(offset)) as P;
    case 4:
      return (reader.readDoubleOrNull(offset) ?? 0.0) as P;
    case 5:
      return (reader.readDoubleOrNull(offset) ?? 0.0) as P;
    case 6:
      return (reader.readBoolOrNull(offset) ?? false) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readLongOrNull(offset) ?? 0) as P;
    case 9:
      return (reader.readLongOrNull(offset) ?? 0) as P;
    case 10:
      return (reader.readStringOrNull(offset) ?? 'completed') as P;
    case 11:
      return (reader.readDoubleOrNull(offset) ?? 0.0) as P;
    case 12:
      return (reader.readDoubleOrNull(offset) ?? 0.0) as P;
    case 13:
      return (reader.readDoubleOrNull(offset) ?? 0.0) as P;
    case 14:
      return (reader.readStringOrNull(offset)) as P;
    case 15:
      return (reader.readDateTime(offset)) as P;
    case 16:
      return (reader.readDouble(offset)) as P;
    case 17:
      return (reader.readDoubleOrNull(offset) ?? 0.0) as P;
    case 18:
      return (reader.readStringOrNull(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _saleTransactionGetId(SaleTransaction object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _saleTransactionGetLinks(SaleTransaction object) {
  return [object.items];
}

void _saleTransactionAttach(
    IsarCollection<dynamic> col, Id id, SaleTransaction object) {
  object.id = id;
  object.items.attach(col, col.isar.collection<SaleItem>(), r'items', id);
}

extension SaleTransactionByIndex on IsarCollection<SaleTransaction> {
  Future<SaleTransaction?> getByTransactionId(String? transactionId) {
    return getByIndex(r'transactionId', [transactionId]);
  }

  SaleTransaction? getByTransactionIdSync(String? transactionId) {
    return getByIndexSync(r'transactionId', [transactionId]);
  }

  Future<bool> deleteByTransactionId(String? transactionId) {
    return deleteByIndex(r'transactionId', [transactionId]);
  }

  bool deleteByTransactionIdSync(String? transactionId) {
    return deleteByIndexSync(r'transactionId', [transactionId]);
  }

  Future<List<SaleTransaction?>> getAllByTransactionId(
      List<String?> transactionIdValues) {
    final values = transactionIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'transactionId', values);
  }

  List<SaleTransaction?> getAllByTransactionIdSync(
      List<String?> transactionIdValues) {
    final values = transactionIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'transactionId', values);
  }

  Future<int> deleteAllByTransactionId(List<String?> transactionIdValues) {
    final values = transactionIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'transactionId', values);
  }

  int deleteAllByTransactionIdSync(List<String?> transactionIdValues) {
    final values = transactionIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'transactionId', values);
  }

  Future<Id> putByTransactionId(SaleTransaction object) {
    return putByIndex(r'transactionId', object);
  }

  Id putByTransactionIdSync(SaleTransaction object, {bool saveLinks = true}) {
    return putByIndexSync(r'transactionId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByTransactionId(List<SaleTransaction> objects) {
    return putAllByIndex(r'transactionId', objects);
  }

  List<Id> putAllByTransactionIdSync(List<SaleTransaction> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'transactionId', objects, saveLinks: saveLinks);
  }
}

extension SaleTransactionQueryWhereSort
    on QueryBuilder<SaleTransaction, SaleTransaction, QWhere> {
  QueryBuilder<SaleTransaction, SaleTransaction, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterWhere> anyTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'timestamp'),
      );
    });
  }
}

extension SaleTransactionQueryWhere
    on QueryBuilder<SaleTransaction, SaleTransaction, QWhereClause> {
  QueryBuilder<SaleTransaction, SaleTransaction, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterWhereClause>
      idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterWhereClause> idLessThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterWhereClause>
      timestampEqualTo(DateTime timestamp) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'timestamp',
        value: [timestamp],
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterWhereClause>
      timestampNotEqualTo(DateTime timestamp) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'timestamp',
              lower: [],
              upper: [timestamp],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'timestamp',
              lower: [timestamp],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'timestamp',
              lower: [timestamp],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'timestamp',
              lower: [],
              upper: [timestamp],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterWhereClause>
      timestampGreaterThan(
    DateTime timestamp, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'timestamp',
        lower: [timestamp],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterWhereClause>
      timestampLessThan(
    DateTime timestamp, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'timestamp',
        lower: [],
        upper: [timestamp],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterWhereClause>
      timestampBetween(
    DateTime lowerTimestamp,
    DateTime upperTimestamp, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'timestamp',
        lower: [lowerTimestamp],
        includeLower: includeLower,
        upper: [upperTimestamp],
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterWhereClause>
      transactionIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'transactionId',
        value: [null],
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterWhereClause>
      transactionIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'transactionId',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterWhereClause>
      transactionIdEqualTo(String? transactionId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'transactionId',
        value: [transactionId],
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterWhereClause>
      transactionIdNotEqualTo(String? transactionId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'transactionId',
              lower: [],
              upper: [transactionId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'transactionId',
              lower: [transactionId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'transactionId',
              lower: [transactionId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'transactionId',
              lower: [],
              upper: [transactionId],
              includeUpper: false,
            ));
      }
    });
  }
}

extension SaleTransactionQueryFilter
    on QueryBuilder<SaleTransaction, SaleTransaction, QFilterCondition> {
  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      cashierIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'cashierId',
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      cashierIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'cashierId',
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      cashierIdEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cashierId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      cashierIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'cashierId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      cashierIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'cashierId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      cashierIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'cashierId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      cashierIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'cashierId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      cashierIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'cashierId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      cashierIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'cashierId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      cashierIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'cashierId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      cashierIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cashierId',
        value: '',
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      cashierIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'cashierId',
        value: '',
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      cashierNameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cashierName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      cashierNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'cashierName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      cashierNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'cashierName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      cashierNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'cashierName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      cashierNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'cashierName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      cashierNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'cashierName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      cashierNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'cashierName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      cashierNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'cashierName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      cashierNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'cashierName',
        value: '',
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      cashierNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'cashierName',
        value: '',
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      changeAmountEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'changeAmount',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      changeAmountGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'changeAmount',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      changeAmountLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'changeAmount',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      changeAmountBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'changeAmount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      customerIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'customerId',
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      customerIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'customerId',
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      customerIdEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'customerId',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      customerIdGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'customerId',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      customerIdLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'customerId',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      customerIdBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'customerId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      discountAmountEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'discountAmount',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      discountAmountGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'discountAmount',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      discountAmountLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'discountAmount',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      discountAmountBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'discountAmount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      grossProfitEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'grossProfit',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      grossProfitGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'grossProfit',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      grossProfitLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'grossProfit',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      grossProfitBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'grossProfit',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      isSyncedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isSynced',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      paymentMethodEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'paymentMethod',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      paymentMethodGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'paymentMethod',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      paymentMethodLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'paymentMethod',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      paymentMethodBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'paymentMethod',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      paymentMethodStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'paymentMethod',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      paymentMethodEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'paymentMethod',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      paymentMethodContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'paymentMethod',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      paymentMethodMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'paymentMethod',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      paymentMethodIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'paymentMethod',
        value: '',
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      paymentMethodIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'paymentMethod',
        value: '',
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      pointsEarnedEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'pointsEarned',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      pointsEarnedGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'pointsEarned',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      pointsEarnedLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'pointsEarned',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      pointsEarnedBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'pointsEarned',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      pointsRedeemedEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'pointsRedeemed',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      pointsRedeemedGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'pointsRedeemed',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      pointsRedeemedLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'pointsRedeemed',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      pointsRedeemedBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'pointsRedeemed',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      statusEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      statusGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      statusLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      statusBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'status',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      statusStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      statusEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      statusContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      statusMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'status',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      statusIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'status',
        value: '',
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      statusIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'status',
        value: '',
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      subtotalEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'subtotal',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      subtotalGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'subtotal',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      subtotalLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'subtotal',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      subtotalBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'subtotal',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      taxAmountEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'taxAmount',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      taxAmountGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'taxAmount',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      taxAmountLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'taxAmount',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      taxAmountBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'taxAmount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      tenderedAmountEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'tenderedAmount',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      tenderedAmountGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'tenderedAmount',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      tenderedAmountLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'tenderedAmount',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      tenderedAmountBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'tenderedAmount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      terminalNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'terminalName',
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      terminalNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'terminalName',
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      terminalNameEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'terminalName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      terminalNameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'terminalName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      terminalNameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'terminalName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      terminalNameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'terminalName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      terminalNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'terminalName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      terminalNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'terminalName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      terminalNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'terminalName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      terminalNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'terminalName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      terminalNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'terminalName',
        value: '',
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      terminalNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'terminalName',
        value: '',
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      timestampEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      timestampGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      timestampLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      timestampBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'timestamp',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      totalAmountEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'totalAmount',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      totalAmountGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'totalAmount',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      totalAmountLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'totalAmount',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      totalAmountBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'totalAmount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      totalCostEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'totalCost',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      totalCostGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'totalCost',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      totalCostLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'totalCost',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      totalCostBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'totalCost',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      transactionIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'transactionId',
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      transactionIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'transactionId',
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      transactionIdEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'transactionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      transactionIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'transactionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      transactionIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'transactionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      transactionIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'transactionId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      transactionIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'transactionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      transactionIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'transactionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      transactionIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'transactionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      transactionIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'transactionId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      transactionIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'transactionId',
        value: '',
      ));
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      transactionIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'transactionId',
        value: '',
      ));
    });
  }
}

extension SaleTransactionQueryObject
    on QueryBuilder<SaleTransaction, SaleTransaction, QFilterCondition> {}

extension SaleTransactionQueryLinks
    on QueryBuilder<SaleTransaction, SaleTransaction, QFilterCondition> {
  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition> items(
      FilterQuery<SaleItem> q) {
    return QueryBuilder.apply(this, (query) {
      return query.link(q, r'items');
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      itemsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'items', length, true, length, true);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      itemsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'items', 0, true, 0, true);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      itemsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'items', 0, false, 999999, true);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      itemsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'items', 0, true, length, include);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      itemsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'items', length, include, 999999, true);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterFilterCondition>
      itemsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(
          r'items', lower, includeLower, upper, includeUpper);
    });
  }
}

extension SaleTransactionQuerySortBy
    on QueryBuilder<SaleTransaction, SaleTransaction, QSortBy> {
  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByCashierId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cashierId', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByCashierIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cashierId', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByCashierName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cashierName', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByCashierNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cashierName', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByChangeAmount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'changeAmount', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByChangeAmountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'changeAmount', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByCustomerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'customerId', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByCustomerIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'customerId', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByDiscountAmount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discountAmount', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByDiscountAmountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discountAmount', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByGrossProfit() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'grossProfit', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByGrossProfitDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'grossProfit', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByIsSyncedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByPaymentMethod() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'paymentMethod', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByPaymentMethodDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'paymentMethod', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByPointsEarned() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pointsEarned', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByPointsEarnedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pointsEarned', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByPointsRedeemed() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pointsRedeemed', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByPointsRedeemedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pointsRedeemed', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy> sortByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortBySubtotal() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subtotal', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortBySubtotalDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subtotal', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByTaxAmount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'taxAmount', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByTaxAmountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'taxAmount', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByTenderedAmount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tenderedAmount', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByTenderedAmountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tenderedAmount', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByTerminalName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'terminalName', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByTerminalNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'terminalName', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByTotalAmount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalAmount', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByTotalAmountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalAmount', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByTotalCost() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalCost', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByTotalCostDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalCost', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByTransactionId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'transactionId', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      sortByTransactionIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'transactionId', Sort.desc);
    });
  }
}

extension SaleTransactionQuerySortThenBy
    on QueryBuilder<SaleTransaction, SaleTransaction, QSortThenBy> {
  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByCashierId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cashierId', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByCashierIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cashierId', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByCashierName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cashierName', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByCashierNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cashierName', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByChangeAmount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'changeAmount', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByChangeAmountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'changeAmount', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByCustomerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'customerId', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByCustomerIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'customerId', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByDiscountAmount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discountAmount', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByDiscountAmountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'discountAmount', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByGrossProfit() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'grossProfit', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByGrossProfitDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'grossProfit', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByIsSyncedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByPaymentMethod() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'paymentMethod', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByPaymentMethodDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'paymentMethod', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByPointsEarned() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pointsEarned', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByPointsEarnedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pointsEarned', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByPointsRedeemed() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pointsRedeemed', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByPointsRedeemedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pointsRedeemed', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy> thenByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenBySubtotal() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subtotal', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenBySubtotalDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subtotal', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByTaxAmount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'taxAmount', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByTaxAmountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'taxAmount', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByTenderedAmount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tenderedAmount', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByTenderedAmountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tenderedAmount', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByTerminalName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'terminalName', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByTerminalNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'terminalName', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByTotalAmount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalAmount', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByTotalAmountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalAmount', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByTotalCost() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalCost', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByTotalCostDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalCost', Sort.desc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByTransactionId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'transactionId', Sort.asc);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QAfterSortBy>
      thenByTransactionIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'transactionId', Sort.desc);
    });
  }
}

extension SaleTransactionQueryWhereDistinct
    on QueryBuilder<SaleTransaction, SaleTransaction, QDistinct> {
  QueryBuilder<SaleTransaction, SaleTransaction, QDistinct> distinctByCashierId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cashierId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QDistinct>
      distinctByCashierName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cashierName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QDistinct>
      distinctByChangeAmount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'changeAmount');
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QDistinct>
      distinctByCustomerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'customerId');
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QDistinct>
      distinctByDiscountAmount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'discountAmount');
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QDistinct>
      distinctByGrossProfit() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'grossProfit');
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QDistinct>
      distinctByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isSynced');
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QDistinct>
      distinctByPaymentMethod({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'paymentMethod',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QDistinct>
      distinctByPointsEarned() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'pointsEarned');
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QDistinct>
      distinctByPointsRedeemed() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'pointsRedeemed');
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QDistinct> distinctByStatus(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'status', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QDistinct>
      distinctBySubtotal() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'subtotal');
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QDistinct>
      distinctByTaxAmount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'taxAmount');
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QDistinct>
      distinctByTenderedAmount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'tenderedAmount');
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QDistinct>
      distinctByTerminalName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'terminalName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QDistinct>
      distinctByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'timestamp');
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QDistinct>
      distinctByTotalAmount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'totalAmount');
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QDistinct>
      distinctByTotalCost() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'totalCost');
    });
  }

  QueryBuilder<SaleTransaction, SaleTransaction, QDistinct>
      distinctByTransactionId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'transactionId',
          caseSensitive: caseSensitive);
    });
  }
}

extension SaleTransactionQueryProperty
    on QueryBuilder<SaleTransaction, SaleTransaction, QQueryProperty> {
  QueryBuilder<SaleTransaction, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<SaleTransaction, String?, QQueryOperations> cashierIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cashierId');
    });
  }

  QueryBuilder<SaleTransaction, String, QQueryOperations>
      cashierNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cashierName');
    });
  }

  QueryBuilder<SaleTransaction, double, QQueryOperations>
      changeAmountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'changeAmount');
    });
  }

  QueryBuilder<SaleTransaction, int?, QQueryOperations> customerIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'customerId');
    });
  }

  QueryBuilder<SaleTransaction, double, QQueryOperations>
      discountAmountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'discountAmount');
    });
  }

  QueryBuilder<SaleTransaction, double, QQueryOperations>
      grossProfitProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'grossProfit');
    });
  }

  QueryBuilder<SaleTransaction, bool, QQueryOperations> isSyncedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isSynced');
    });
  }

  QueryBuilder<SaleTransaction, String, QQueryOperations>
      paymentMethodProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'paymentMethod');
    });
  }

  QueryBuilder<SaleTransaction, int, QQueryOperations> pointsEarnedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'pointsEarned');
    });
  }

  QueryBuilder<SaleTransaction, int, QQueryOperations>
      pointsRedeemedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'pointsRedeemed');
    });
  }

  QueryBuilder<SaleTransaction, String, QQueryOperations> statusProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'status');
    });
  }

  QueryBuilder<SaleTransaction, double, QQueryOperations> subtotalProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'subtotal');
    });
  }

  QueryBuilder<SaleTransaction, double, QQueryOperations> taxAmountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'taxAmount');
    });
  }

  QueryBuilder<SaleTransaction, double, QQueryOperations>
      tenderedAmountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'tenderedAmount');
    });
  }

  QueryBuilder<SaleTransaction, String?, QQueryOperations>
      terminalNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'terminalName');
    });
  }

  QueryBuilder<SaleTransaction, DateTime, QQueryOperations>
      timestampProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'timestamp');
    });
  }

  QueryBuilder<SaleTransaction, double, QQueryOperations>
      totalAmountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'totalAmount');
    });
  }

  QueryBuilder<SaleTransaction, double, QQueryOperations> totalCostProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'totalCost');
    });
  }

  QueryBuilder<SaleTransaction, String?, QQueryOperations>
      transactionIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'transactionId');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetSaleItemCollection on Isar {
  IsarCollection<SaleItem> get saleItems => this.collection();
}

const SaleItemSchema = CollectionSchema(
  name: r'SaleItem',
  id: 8503636501889557541,
  properties: {
    r'isRefunded': PropertySchema(
      id: 0,
      name: r'isRefunded',
      type: IsarType.bool,
    ),
    r'isTaxInclusiveAtSale': PropertySchema(
      id: 1,
      name: r'isTaxInclusiveAtSale',
      type: IsarType.bool,
    ),
    r'priceAtSale': PropertySchema(
      id: 2,
      name: r'priceAtSale',
      type: IsarType.double,
    ),
    r'productId': PropertySchema(
      id: 3,
      name: r'productId',
      type: IsarType.long,
    ),
    r'productName': PropertySchema(
      id: 4,
      name: r'productName',
      type: IsarType.string,
    ),
    r'quantity': PropertySchema(
      id: 5,
      name: r'quantity',
      type: IsarType.long,
    ),
    r'taxRateAtSale': PropertySchema(
      id: 6,
      name: r'taxRateAtSale',
      type: IsarType.double,
    ),
    r'unitCostAtSale': PropertySchema(
      id: 7,
      name: r'unitCostAtSale',
      type: IsarType.double,
    )
  },
  estimateSize: _saleItemEstimateSize,
  serialize: _saleItemSerialize,
  deserialize: _saleItemDeserialize,
  deserializeProp: _saleItemDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _saleItemGetId,
  getLinks: _saleItemGetLinks,
  attach: _saleItemAttach,
  version: '3.1.0+1',
);

int _saleItemEstimateSize(
  SaleItem object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.productName.length * 3;
  return bytesCount;
}

void _saleItemSerialize(
  SaleItem object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeBool(offsets[0], object.isRefunded);
  writer.writeBool(offsets[1], object.isTaxInclusiveAtSale);
  writer.writeDouble(offsets[2], object.priceAtSale);
  writer.writeLong(offsets[3], object.productId);
  writer.writeString(offsets[4], object.productName);
  writer.writeLong(offsets[5], object.quantity);
  writer.writeDouble(offsets[6], object.taxRateAtSale);
  writer.writeDouble(offsets[7], object.unitCostAtSale);
}

SaleItem _saleItemDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = SaleItem(
    isRefunded: reader.readBoolOrNull(offsets[0]) ?? false,
    isTaxInclusiveAtSale: reader.readBoolOrNull(offsets[1]) ?? true,
    priceAtSale: reader.readDouble(offsets[2]),
    productId: reader.readLong(offsets[3]),
    productName: reader.readString(offsets[4]),
    quantity: reader.readLongOrNull(offsets[5]) ?? 1,
    taxRateAtSale: reader.readDoubleOrNull(offsets[6]) ?? 0.0,
    unitCostAtSale: reader.readDoubleOrNull(offsets[7]) ?? 0.0,
  );
  object.id = id;
  return object;
}

P _saleItemDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readBoolOrNull(offset) ?? false) as P;
    case 1:
      return (reader.readBoolOrNull(offset) ?? true) as P;
    case 2:
      return (reader.readDouble(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readLongOrNull(offset) ?? 1) as P;
    case 6:
      return (reader.readDoubleOrNull(offset) ?? 0.0) as P;
    case 7:
      return (reader.readDoubleOrNull(offset) ?? 0.0) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _saleItemGetId(SaleItem object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _saleItemGetLinks(SaleItem object) {
  return [];
}

void _saleItemAttach(IsarCollection<dynamic> col, Id id, SaleItem object) {
  object.id = id;
}

extension SaleItemQueryWhereSort on QueryBuilder<SaleItem, SaleItem, QWhere> {
  QueryBuilder<SaleItem, SaleItem, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension SaleItemQueryWhere on QueryBuilder<SaleItem, SaleItem, QWhereClause> {
  QueryBuilder<SaleItem, SaleItem, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension SaleItemQueryFilter
    on QueryBuilder<SaleItem, SaleItem, QFilterCondition> {
  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> isRefundedEqualTo(
      bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isRefunded',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition>
      isTaxInclusiveAtSaleEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isTaxInclusiveAtSale',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> priceAtSaleEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'priceAtSale',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition>
      priceAtSaleGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'priceAtSale',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> priceAtSaleLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'priceAtSale',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> priceAtSaleBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'priceAtSale',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> productIdEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'productId',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> productIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'productId',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> productIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'productId',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> productIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'productId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> productNameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'productName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition>
      productNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'productName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> productNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'productName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> productNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'productName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> productNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'productName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> productNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'productName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> productNameContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'productName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> productNameMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'productName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> productNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'productName',
        value: '',
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition>
      productNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'productName',
        value: '',
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> quantityEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'quantity',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> quantityGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'quantity',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> quantityLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'quantity',
        value: value,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> quantityBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'quantity',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> taxRateAtSaleEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'taxRateAtSale',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition>
      taxRateAtSaleGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'taxRateAtSale',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> taxRateAtSaleLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'taxRateAtSale',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> taxRateAtSaleBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'taxRateAtSale',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> unitCostAtSaleEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'unitCostAtSale',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition>
      unitCostAtSaleGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'unitCostAtSale',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition>
      unitCostAtSaleLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'unitCostAtSale',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterFilterCondition> unitCostAtSaleBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'unitCostAtSale',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }
}

extension SaleItemQueryObject
    on QueryBuilder<SaleItem, SaleItem, QFilterCondition> {}

extension SaleItemQueryLinks
    on QueryBuilder<SaleItem, SaleItem, QFilterCondition> {}

extension SaleItemQuerySortBy on QueryBuilder<SaleItem, SaleItem, QSortBy> {
  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> sortByIsRefunded() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isRefunded', Sort.asc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> sortByIsRefundedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isRefunded', Sort.desc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> sortByIsTaxInclusiveAtSale() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isTaxInclusiveAtSale', Sort.asc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy>
      sortByIsTaxInclusiveAtSaleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isTaxInclusiveAtSale', Sort.desc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> sortByPriceAtSale() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'priceAtSale', Sort.asc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> sortByPriceAtSaleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'priceAtSale', Sort.desc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> sortByProductId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'productId', Sort.asc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> sortByProductIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'productId', Sort.desc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> sortByProductName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'productName', Sort.asc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> sortByProductNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'productName', Sort.desc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> sortByQuantity() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'quantity', Sort.asc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> sortByQuantityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'quantity', Sort.desc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> sortByTaxRateAtSale() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'taxRateAtSale', Sort.asc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> sortByTaxRateAtSaleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'taxRateAtSale', Sort.desc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> sortByUnitCostAtSale() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'unitCostAtSale', Sort.asc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> sortByUnitCostAtSaleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'unitCostAtSale', Sort.desc);
    });
  }
}

extension SaleItemQuerySortThenBy
    on QueryBuilder<SaleItem, SaleItem, QSortThenBy> {
  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> thenByIsRefunded() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isRefunded', Sort.asc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> thenByIsRefundedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isRefunded', Sort.desc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> thenByIsTaxInclusiveAtSale() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isTaxInclusiveAtSale', Sort.asc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy>
      thenByIsTaxInclusiveAtSaleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isTaxInclusiveAtSale', Sort.desc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> thenByPriceAtSale() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'priceAtSale', Sort.asc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> thenByPriceAtSaleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'priceAtSale', Sort.desc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> thenByProductId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'productId', Sort.asc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> thenByProductIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'productId', Sort.desc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> thenByProductName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'productName', Sort.asc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> thenByProductNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'productName', Sort.desc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> thenByQuantity() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'quantity', Sort.asc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> thenByQuantityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'quantity', Sort.desc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> thenByTaxRateAtSale() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'taxRateAtSale', Sort.asc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> thenByTaxRateAtSaleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'taxRateAtSale', Sort.desc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> thenByUnitCostAtSale() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'unitCostAtSale', Sort.asc);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QAfterSortBy> thenByUnitCostAtSaleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'unitCostAtSale', Sort.desc);
    });
  }
}

extension SaleItemQueryWhereDistinct
    on QueryBuilder<SaleItem, SaleItem, QDistinct> {
  QueryBuilder<SaleItem, SaleItem, QDistinct> distinctByIsRefunded() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isRefunded');
    });
  }

  QueryBuilder<SaleItem, SaleItem, QDistinct> distinctByIsTaxInclusiveAtSale() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isTaxInclusiveAtSale');
    });
  }

  QueryBuilder<SaleItem, SaleItem, QDistinct> distinctByPriceAtSale() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'priceAtSale');
    });
  }

  QueryBuilder<SaleItem, SaleItem, QDistinct> distinctByProductId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'productId');
    });
  }

  QueryBuilder<SaleItem, SaleItem, QDistinct> distinctByProductName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'productName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SaleItem, SaleItem, QDistinct> distinctByQuantity() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'quantity');
    });
  }

  QueryBuilder<SaleItem, SaleItem, QDistinct> distinctByTaxRateAtSale() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'taxRateAtSale');
    });
  }

  QueryBuilder<SaleItem, SaleItem, QDistinct> distinctByUnitCostAtSale() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'unitCostAtSale');
    });
  }
}

extension SaleItemQueryProperty
    on QueryBuilder<SaleItem, SaleItem, QQueryProperty> {
  QueryBuilder<SaleItem, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<SaleItem, bool, QQueryOperations> isRefundedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isRefunded');
    });
  }

  QueryBuilder<SaleItem, bool, QQueryOperations>
      isTaxInclusiveAtSaleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isTaxInclusiveAtSale');
    });
  }

  QueryBuilder<SaleItem, double, QQueryOperations> priceAtSaleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'priceAtSale');
    });
  }

  QueryBuilder<SaleItem, int, QQueryOperations> productIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'productId');
    });
  }

  QueryBuilder<SaleItem, String, QQueryOperations> productNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'productName');
    });
  }

  QueryBuilder<SaleItem, int, QQueryOperations> quantityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'quantity');
    });
  }

  QueryBuilder<SaleItem, double, QQueryOperations> taxRateAtSaleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'taxRateAtSale');
    });
  }

  QueryBuilder<SaleItem, double, QQueryOperations> unitCostAtSaleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'unitCostAtSale');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetAttendanceLogCollection on Isar {
  IsarCollection<AttendanceLog> get attendanceLogs => this.collection();
}

const AttendanceLogSchema = CollectionSchema(
  name: r'AttendanceLog',
  id: 1511539404068289100,
  properties: {
    r'timestamp': PropertySchema(
      id: 0,
      name: r'timestamp',
      type: IsarType.dateTime,
    ),
    r'type': PropertySchema(
      id: 1,
      name: r'type',
      type: IsarType.string,
    ),
    r'userId': PropertySchema(
      id: 2,
      name: r'userId',
      type: IsarType.long,
    ),
    r'username': PropertySchema(
      id: 3,
      name: r'username',
      type: IsarType.string,
    )
  },
  estimateSize: _attendanceLogEstimateSize,
  serialize: _attendanceLogSerialize,
  deserialize: _attendanceLogDeserialize,
  deserializeProp: _attendanceLogDeserializeProp,
  idName: r'id',
  indexes: {
    r'timestamp': IndexSchema(
      id: 1852253767416892198,
      name: r'timestamp',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'timestamp',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _attendanceLogGetId,
  getLinks: _attendanceLogGetLinks,
  attach: _attendanceLogAttach,
  version: '3.1.0+1',
);

int _attendanceLogEstimateSize(
  AttendanceLog object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.type.length * 3;
  bytesCount += 3 + object.username.length * 3;
  return bytesCount;
}

void _attendanceLogSerialize(
  AttendanceLog object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDateTime(offsets[0], object.timestamp);
  writer.writeString(offsets[1], object.type);
  writer.writeLong(offsets[2], object.userId);
  writer.writeString(offsets[3], object.username);
}

AttendanceLog _attendanceLogDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = AttendanceLog();
  object.id = id;
  object.timestamp = reader.readDateTime(offsets[0]);
  object.type = reader.readString(offsets[1]);
  object.userId = reader.readLong(offsets[2]);
  object.username = reader.readString(offsets[3]);
  return object;
}

P _attendanceLogDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDateTime(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _attendanceLogGetId(AttendanceLog object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _attendanceLogGetLinks(AttendanceLog object) {
  return [];
}

void _attendanceLogAttach(
    IsarCollection<dynamic> col, Id id, AttendanceLog object) {
  object.id = id;
}

extension AttendanceLogQueryWhereSort
    on QueryBuilder<AttendanceLog, AttendanceLog, QWhere> {
  QueryBuilder<AttendanceLog, AttendanceLog, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterWhere> anyTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'timestamp'),
      );
    });
  }
}

extension AttendanceLogQueryWhere
    on QueryBuilder<AttendanceLog, AttendanceLog, QWhereClause> {
  QueryBuilder<AttendanceLog, AttendanceLog, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterWhereClause> idNotEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterWhereClause> idGreaterThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterWhereClause> idLessThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterWhereClause>
      timestampEqualTo(DateTime timestamp) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'timestamp',
        value: [timestamp],
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterWhereClause>
      timestampNotEqualTo(DateTime timestamp) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'timestamp',
              lower: [],
              upper: [timestamp],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'timestamp',
              lower: [timestamp],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'timestamp',
              lower: [timestamp],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'timestamp',
              lower: [],
              upper: [timestamp],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterWhereClause>
      timestampGreaterThan(
    DateTime timestamp, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'timestamp',
        lower: [timestamp],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterWhereClause>
      timestampLessThan(
    DateTime timestamp, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'timestamp',
        lower: [],
        upper: [timestamp],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterWhereClause>
      timestampBetween(
    DateTime lowerTimestamp,
    DateTime upperTimestamp, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'timestamp',
        lower: [lowerTimestamp],
        includeLower: includeLower,
        upper: [upperTimestamp],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension AttendanceLogQueryFilter
    on QueryBuilder<AttendanceLog, AttendanceLog, QFilterCondition> {
  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      timestampEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      timestampGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      timestampLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      timestampBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'timestamp',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition> typeEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      typeGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      typeLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition> typeBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'type',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      typeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      typeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      typeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition> typeMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'type',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      typeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'type',
        value: '',
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      typeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'type',
        value: '',
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      userIdEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'userId',
        value: value,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      userIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'userId',
        value: value,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      userIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'userId',
        value: value,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      userIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'userId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      usernameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'username',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      usernameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'username',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      usernameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'username',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      usernameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'username',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      usernameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'username',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      usernameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'username',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      usernameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'username',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      usernameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'username',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      usernameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'username',
        value: '',
      ));
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterFilterCondition>
      usernameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'username',
        value: '',
      ));
    });
  }
}

extension AttendanceLogQueryObject
    on QueryBuilder<AttendanceLog, AttendanceLog, QFilterCondition> {}

extension AttendanceLogQueryLinks
    on QueryBuilder<AttendanceLog, AttendanceLog, QFilterCondition> {}

extension AttendanceLogQuerySortBy
    on QueryBuilder<AttendanceLog, AttendanceLog, QSortBy> {
  QueryBuilder<AttendanceLog, AttendanceLog, QAfterSortBy> sortByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.asc);
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterSortBy>
      sortByTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.desc);
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterSortBy> sortByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.asc);
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterSortBy> sortByTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.desc);
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterSortBy> sortByUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userId', Sort.asc);
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterSortBy> sortByUserIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userId', Sort.desc);
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterSortBy> sortByUsername() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'username', Sort.asc);
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterSortBy>
      sortByUsernameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'username', Sort.desc);
    });
  }
}

extension AttendanceLogQuerySortThenBy
    on QueryBuilder<AttendanceLog, AttendanceLog, QSortThenBy> {
  QueryBuilder<AttendanceLog, AttendanceLog, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterSortBy> thenByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.asc);
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterSortBy>
      thenByTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.desc);
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterSortBy> thenByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.asc);
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterSortBy> thenByTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.desc);
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterSortBy> thenByUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userId', Sort.asc);
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterSortBy> thenByUserIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userId', Sort.desc);
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterSortBy> thenByUsername() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'username', Sort.asc);
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QAfterSortBy>
      thenByUsernameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'username', Sort.desc);
    });
  }
}

extension AttendanceLogQueryWhereDistinct
    on QueryBuilder<AttendanceLog, AttendanceLog, QDistinct> {
  QueryBuilder<AttendanceLog, AttendanceLog, QDistinct> distinctByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'timestamp');
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QDistinct> distinctByType(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'type', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QDistinct> distinctByUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'userId');
    });
  }

  QueryBuilder<AttendanceLog, AttendanceLog, QDistinct> distinctByUsername(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'username', caseSensitive: caseSensitive);
    });
  }
}

extension AttendanceLogQueryProperty
    on QueryBuilder<AttendanceLog, AttendanceLog, QQueryProperty> {
  QueryBuilder<AttendanceLog, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<AttendanceLog, DateTime, QQueryOperations> timestampProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'timestamp');
    });
  }

  QueryBuilder<AttendanceLog, String, QQueryOperations> typeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'type');
    });
  }

  QueryBuilder<AttendanceLog, int, QQueryOperations> userIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'userId');
    });
  }

  QueryBuilder<AttendanceLog, String, QQueryOperations> usernameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'username');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetStoreConfigCollection on Isar {
  IsarCollection<StoreConfig> get storeConfigs => this.collection();
}

const StoreConfigSchema = CollectionSchema(
  name: r'StoreConfig',
  id: 2883021225625652483,
  properties: {
    r'address': PropertySchema(
      id: 0,
      name: r'address',
      type: IsarType.string,
    ),
    r'autoPrintReceipt': PropertySchema(
      id: 1,
      name: r'autoPrintReceipt',
      type: IsarType.bool,
    ),
    r'backupPath': PropertySchema(
      id: 2,
      name: r'backupPath',
      type: IsarType.string,
    ),
    r'branchName': PropertySchema(
      id: 3,
      name: r'branchName',
      type: IsarType.string,
    ),
    r'brandColorHex': PropertySchema(
      id: 4,
      name: r'brandColorHex',
      type: IsarType.string,
    ),
    r'businessName': PropertySchema(
      id: 5,
      name: r'businessName',
      type: IsarType.string,
    ),
    r'contactNumber': PropertySchema(
      id: 6,
      name: r'contactNumber',
      type: IsarType.string,
    ),
    r'currencySymbol': PropertySchema(
      id: 7,
      name: r'currencySymbol',
      type: IsarType.string,
    ),
    r'defaultPrinterAddress': PropertySchema(
      id: 8,
      name: r'defaultPrinterAddress',
      type: IsarType.string,
    ),
    r'defaultPrinterModel': PropertySchema(
      id: 9,
      name: r'defaultPrinterModel',
      type: IsarType.string,
    ),
    r'defaultPrinterName': PropertySchema(
      id: 10,
      name: r'defaultPrinterName',
      type: IsarType.string,
    ),
    r'defaultPrinterType': PropertySchema(
      id: 11,
      name: r'defaultPrinterType',
      type: IsarType.string,
    ),
    r'email': PropertySchema(
      id: 12,
      name: r'email',
      type: IsarType.string,
    ),
    r'isManagerMode': PropertySchema(
      id: 13,
      name: r'isManagerMode',
      type: IsarType.bool,
    ),
    r'lastBackupDate': PropertySchema(
      id: 14,
      name: r'lastBackupDate',
      type: IsarType.dateTime,
    ),
    r'logoPath': PropertySchema(
      id: 15,
      name: r'logoPath',
      type: IsarType.string,
    ),
    r'loyaltyEarnRate': PropertySchema(
      id: 16,
      name: r'loyaltyEarnRate',
      type: IsarType.double,
    ),
    r'loyaltyEnabled': PropertySchema(
      id: 17,
      name: r'loyaltyEnabled',
      type: IsarType.bool,
    ),
    r'loyaltyRedemptionValue': PropertySchema(
      id: 18,
      name: r'loyaltyRedemptionValue',
      type: IsarType.double,
    ),
    r'mrcNo': PropertySchema(
      id: 19,
      name: r'mrcNo',
      type: IsarType.string,
    ),
    r'paperWidthMm': PropertySchema(
      id: 20,
      name: r'paperWidthMm',
      type: IsarType.long,
    ),
    r'port': PropertySchema(
      id: 21,
      name: r'port',
      type: IsarType.long,
    ),
    r'primarySector': PropertySchema(
      id: 22,
      name: r'primarySector',
      type: IsarType.byte,
      enumMap: _StoreConfigprimarySectorEnumValueMap,
    ),
    r'recoveryCodeHash': PropertySchema(
      id: 23,
      name: r'recoveryCodeHash',
      type: IsarType.string,
    ),
    r'sdcId': PropertySchema(
      id: 24,
      name: r'sdcId',
      type: IsarType.string,
    ),
    r'serverIp': PropertySchema(
      id: 25,
      name: r'serverIp',
      type: IsarType.string,
    ),
    r'taxId': PropertySchema(
      id: 26,
      name: r'taxId',
      type: IsarType.string,
    ),
    r'taxRate': PropertySchema(
      id: 27,
      name: r'taxRate',
      type: IsarType.double,
    ),
    r'terminalName': PropertySchema(
      id: 28,
      name: r'terminalName',
      type: IsarType.string,
    ),
    r'tpin': PropertySchema(
      id: 29,
      name: r'tpin',
      type: IsarType.string,
    ),
    r'website': PropertySchema(
      id: 30,
      name: r'website',
      type: IsarType.string,
    )
  },
  estimateSize: _storeConfigEstimateSize,
  serialize: _storeConfigSerialize,
  deserialize: _storeConfigDeserialize,
  deserializeProp: _storeConfigDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _storeConfigGetId,
  getLinks: _storeConfigGetLinks,
  attach: _storeConfigAttach,
  version: '3.1.0+1',
);

int _storeConfigEstimateSize(
  StoreConfig object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.address;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.backupPath;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.branchName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.brandColorHex;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.businessName.length * 3;
  {
    final value = object.contactNumber;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.currencySymbol;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.defaultPrinterAddress;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.defaultPrinterModel;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.defaultPrinterName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.defaultPrinterType;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.email;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.logoPath;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.mrcNo;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.recoveryCodeHash;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.sdcId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.serverIp;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.taxId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.terminalName.length * 3;
  {
    final value = object.tpin;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.website;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _storeConfigSerialize(
  StoreConfig object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.address);
  writer.writeBool(offsets[1], object.autoPrintReceipt);
  writer.writeString(offsets[2], object.backupPath);
  writer.writeString(offsets[3], object.branchName);
  writer.writeString(offsets[4], object.brandColorHex);
  writer.writeString(offsets[5], object.businessName);
  writer.writeString(offsets[6], object.contactNumber);
  writer.writeString(offsets[7], object.currencySymbol);
  writer.writeString(offsets[8], object.defaultPrinterAddress);
  writer.writeString(offsets[9], object.defaultPrinterModel);
  writer.writeString(offsets[10], object.defaultPrinterName);
  writer.writeString(offsets[11], object.defaultPrinterType);
  writer.writeString(offsets[12], object.email);
  writer.writeBool(offsets[13], object.isManagerMode);
  writer.writeDateTime(offsets[14], object.lastBackupDate);
  writer.writeString(offsets[15], object.logoPath);
  writer.writeDouble(offsets[16], object.loyaltyEarnRate);
  writer.writeBool(offsets[17], object.loyaltyEnabled);
  writer.writeDouble(offsets[18], object.loyaltyRedemptionValue);
  writer.writeString(offsets[19], object.mrcNo);
  writer.writeLong(offsets[20], object.paperWidthMm);
  writer.writeLong(offsets[21], object.port);
  writer.writeByte(offsets[22], object.primarySector.index);
  writer.writeString(offsets[23], object.recoveryCodeHash);
  writer.writeString(offsets[24], object.sdcId);
  writer.writeString(offsets[25], object.serverIp);
  writer.writeString(offsets[26], object.taxId);
  writer.writeDouble(offsets[27], object.taxRate);
  writer.writeString(offsets[28], object.terminalName);
  writer.writeString(offsets[29], object.tpin);
  writer.writeString(offsets[30], object.website);
}

StoreConfig _storeConfigDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = StoreConfig();
  object.address = reader.readStringOrNull(offsets[0]);
  object.autoPrintReceipt = reader.readBool(offsets[1]);
  object.backupPath = reader.readStringOrNull(offsets[2]);
  object.branchName = reader.readStringOrNull(offsets[3]);
  object.brandColorHex = reader.readStringOrNull(offsets[4]);
  object.businessName = reader.readString(offsets[5]);
  object.contactNumber = reader.readStringOrNull(offsets[6]);
  object.currencySymbol = reader.readStringOrNull(offsets[7]);
  object.defaultPrinterAddress = reader.readStringOrNull(offsets[8]);
  object.defaultPrinterModel = reader.readStringOrNull(offsets[9]);
  object.defaultPrinterName = reader.readStringOrNull(offsets[10]);
  object.defaultPrinterType = reader.readStringOrNull(offsets[11]);
  object.email = reader.readStringOrNull(offsets[12]);
  object.id = id;
  object.isManagerMode = reader.readBool(offsets[13]);
  object.lastBackupDate = reader.readDateTimeOrNull(offsets[14]);
  object.logoPath = reader.readStringOrNull(offsets[15]);
  object.loyaltyEarnRate = reader.readDouble(offsets[16]);
  object.loyaltyEnabled = reader.readBool(offsets[17]);
  object.loyaltyRedemptionValue = reader.readDouble(offsets[18]);
  object.mrcNo = reader.readStringOrNull(offsets[19]);
  object.paperWidthMm = reader.readLong(offsets[20]);
  object.port = reader.readLong(offsets[21]);
  object.primarySector = _StoreConfigprimarySectorValueEnumMap[
          reader.readByteOrNull(offsets[22])] ??
      CategorySector.pharmacy;
  object.recoveryCodeHash = reader.readStringOrNull(offsets[23]);
  object.sdcId = reader.readStringOrNull(offsets[24]);
  object.serverIp = reader.readStringOrNull(offsets[25]);
  object.taxId = reader.readStringOrNull(offsets[26]);
  object.taxRate = reader.readDouble(offsets[27]);
  object.terminalName = reader.readString(offsets[28]);
  object.tpin = reader.readStringOrNull(offsets[29]);
  object.website = reader.readStringOrNull(offsets[30]);
  return object;
}

P _storeConfigDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (reader.readBool(offset)) as P;
    case 2:
      return (reader.readStringOrNull(offset)) as P;
    case 3:
      return (reader.readStringOrNull(offset)) as P;
    case 4:
      return (reader.readStringOrNull(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readStringOrNull(offset)) as P;
    case 7:
      return (reader.readStringOrNull(offset)) as P;
    case 8:
      return (reader.readStringOrNull(offset)) as P;
    case 9:
      return (reader.readStringOrNull(offset)) as P;
    case 10:
      return (reader.readStringOrNull(offset)) as P;
    case 11:
      return (reader.readStringOrNull(offset)) as P;
    case 12:
      return (reader.readStringOrNull(offset)) as P;
    case 13:
      return (reader.readBool(offset)) as P;
    case 14:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 15:
      return (reader.readStringOrNull(offset)) as P;
    case 16:
      return (reader.readDouble(offset)) as P;
    case 17:
      return (reader.readBool(offset)) as P;
    case 18:
      return (reader.readDouble(offset)) as P;
    case 19:
      return (reader.readStringOrNull(offset)) as P;
    case 20:
      return (reader.readLong(offset)) as P;
    case 21:
      return (reader.readLong(offset)) as P;
    case 22:
      return (_StoreConfigprimarySectorValueEnumMap[
              reader.readByteOrNull(offset)] ??
          CategorySector.pharmacy) as P;
    case 23:
      return (reader.readStringOrNull(offset)) as P;
    case 24:
      return (reader.readStringOrNull(offset)) as P;
    case 25:
      return (reader.readStringOrNull(offset)) as P;
    case 26:
      return (reader.readStringOrNull(offset)) as P;
    case 27:
      return (reader.readDouble(offset)) as P;
    case 28:
      return (reader.readString(offset)) as P;
    case 29:
      return (reader.readStringOrNull(offset)) as P;
    case 30:
      return (reader.readStringOrNull(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

const _StoreConfigprimarySectorEnumValueMap = {
  'pharmacy': 0,
  'stationery': 1,
  'grocery': 2,
  'food': 3,
  'restaurant': 4,
  'other': 5,
};
const _StoreConfigprimarySectorValueEnumMap = {
  0: CategorySector.pharmacy,
  1: CategorySector.stationery,
  2: CategorySector.grocery,
  3: CategorySector.food,
  4: CategorySector.restaurant,
  5: CategorySector.other,
};

Id _storeConfigGetId(StoreConfig object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _storeConfigGetLinks(StoreConfig object) {
  return [];
}

void _storeConfigAttach(
    IsarCollection<dynamic> col, Id id, StoreConfig object) {
  object.id = id;
}

extension StoreConfigQueryWhereSort
    on QueryBuilder<StoreConfig, StoreConfig, QWhere> {
  QueryBuilder<StoreConfig, StoreConfig, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension StoreConfigQueryWhere
    on QueryBuilder<StoreConfig, StoreConfig, QWhereClause> {
  QueryBuilder<StoreConfig, StoreConfig, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterWhereClause> idNotEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension StoreConfigQueryFilter
    on QueryBuilder<StoreConfig, StoreConfig, QFilterCondition> {
  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      addressIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'address',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      addressIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'address',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> addressEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'address',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      addressGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'address',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> addressLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'address',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> addressBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'address',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      addressStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'address',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> addressEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'address',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> addressContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'address',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> addressMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'address',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      addressIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'address',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      addressIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'address',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      autoPrintReceiptEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'autoPrintReceipt',
        value: value,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      backupPathIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'backupPath',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      backupPathIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'backupPath',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      backupPathEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'backupPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      backupPathGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'backupPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      backupPathLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'backupPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      backupPathBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'backupPath',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      backupPathStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'backupPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      backupPathEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'backupPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      backupPathContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'backupPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      backupPathMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'backupPath',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      backupPathIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'backupPath',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      backupPathIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'backupPath',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      branchNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'branchName',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      branchNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'branchName',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      branchNameEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'branchName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      branchNameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'branchName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      branchNameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'branchName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      branchNameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'branchName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      branchNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'branchName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      branchNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'branchName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      branchNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'branchName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      branchNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'branchName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      branchNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'branchName',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      branchNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'branchName',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      brandColorHexIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'brandColorHex',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      brandColorHexIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'brandColorHex',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      brandColorHexEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'brandColorHex',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      brandColorHexGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'brandColorHex',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      brandColorHexLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'brandColorHex',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      brandColorHexBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'brandColorHex',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      brandColorHexStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'brandColorHex',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      brandColorHexEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'brandColorHex',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      brandColorHexContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'brandColorHex',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      brandColorHexMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'brandColorHex',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      brandColorHexIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'brandColorHex',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      brandColorHexIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'brandColorHex',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      businessNameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'businessName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      businessNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'businessName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      businessNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'businessName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      businessNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'businessName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      businessNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'businessName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      businessNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'businessName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      businessNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'businessName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      businessNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'businessName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      businessNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'businessName',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      businessNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'businessName',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      contactNumberIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'contactNumber',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      contactNumberIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'contactNumber',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      contactNumberEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'contactNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      contactNumberGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'contactNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      contactNumberLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'contactNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      contactNumberBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'contactNumber',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      contactNumberStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'contactNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      contactNumberEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'contactNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      contactNumberContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'contactNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      contactNumberMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'contactNumber',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      contactNumberIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'contactNumber',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      contactNumberIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'contactNumber',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      currencySymbolIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'currencySymbol',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      currencySymbolIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'currencySymbol',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      currencySymbolEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'currencySymbol',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      currencySymbolGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'currencySymbol',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      currencySymbolLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'currencySymbol',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      currencySymbolBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'currencySymbol',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      currencySymbolStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'currencySymbol',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      currencySymbolEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'currencySymbol',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      currencySymbolContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'currencySymbol',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      currencySymbolMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'currencySymbol',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      currencySymbolIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'currencySymbol',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      currencySymbolIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'currencySymbol',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterAddressIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'defaultPrinterAddress',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterAddressIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'defaultPrinterAddress',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterAddressEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'defaultPrinterAddress',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterAddressGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'defaultPrinterAddress',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterAddressLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'defaultPrinterAddress',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterAddressBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'defaultPrinterAddress',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterAddressStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'defaultPrinterAddress',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterAddressEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'defaultPrinterAddress',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterAddressContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'defaultPrinterAddress',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterAddressMatches(String pattern,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'defaultPrinterAddress',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterAddressIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'defaultPrinterAddress',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterAddressIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'defaultPrinterAddress',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterModelIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'defaultPrinterModel',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterModelIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'defaultPrinterModel',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterModelEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'defaultPrinterModel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterModelGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'defaultPrinterModel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterModelLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'defaultPrinterModel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterModelBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'defaultPrinterModel',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterModelStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'defaultPrinterModel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterModelEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'defaultPrinterModel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterModelContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'defaultPrinterModel',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterModelMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'defaultPrinterModel',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterModelIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'defaultPrinterModel',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterModelIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'defaultPrinterModel',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'defaultPrinterName',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'defaultPrinterName',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterNameEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'defaultPrinterName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterNameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'defaultPrinterName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterNameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'defaultPrinterName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterNameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'defaultPrinterName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'defaultPrinterName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'defaultPrinterName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'defaultPrinterName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'defaultPrinterName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'defaultPrinterName',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'defaultPrinterName',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterTypeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'defaultPrinterType',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterTypeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'defaultPrinterType',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterTypeEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'defaultPrinterType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterTypeGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'defaultPrinterType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterTypeLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'defaultPrinterType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterTypeBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'defaultPrinterType',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterTypeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'defaultPrinterType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterTypeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'defaultPrinterType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterTypeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'defaultPrinterType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterTypeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'defaultPrinterType',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterTypeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'defaultPrinterType',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      defaultPrinterTypeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'defaultPrinterType',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> emailIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'email',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      emailIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'email',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> emailEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'email',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      emailGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'email',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> emailLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'email',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> emailBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'email',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> emailStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'email',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> emailEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'email',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> emailContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'email',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> emailMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'email',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> emailIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'email',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      emailIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'email',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      isManagerModeEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isManagerMode',
        value: value,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      lastBackupDateIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'lastBackupDate',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      lastBackupDateIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'lastBackupDate',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      lastBackupDateEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastBackupDate',
        value: value,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      lastBackupDateGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lastBackupDate',
        value: value,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      lastBackupDateLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lastBackupDate',
        value: value,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      lastBackupDateBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lastBackupDate',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      logoPathIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'logoPath',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      logoPathIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'logoPath',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> logoPathEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'logoPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      logoPathGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'logoPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      logoPathLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'logoPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> logoPathBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'logoPath',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      logoPathStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'logoPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      logoPathEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'logoPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      logoPathContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'logoPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> logoPathMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'logoPath',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      logoPathIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'logoPath',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      logoPathIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'logoPath',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      loyaltyEarnRateEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'loyaltyEarnRate',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      loyaltyEarnRateGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'loyaltyEarnRate',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      loyaltyEarnRateLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'loyaltyEarnRate',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      loyaltyEarnRateBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'loyaltyEarnRate',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      loyaltyEnabledEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'loyaltyEnabled',
        value: value,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      loyaltyRedemptionValueEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'loyaltyRedemptionValue',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      loyaltyRedemptionValueGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'loyaltyRedemptionValue',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      loyaltyRedemptionValueLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'loyaltyRedemptionValue',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      loyaltyRedemptionValueBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'loyaltyRedemptionValue',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> mrcNoIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'mrcNo',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      mrcNoIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'mrcNo',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> mrcNoEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'mrcNo',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      mrcNoGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'mrcNo',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> mrcNoLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'mrcNo',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> mrcNoBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'mrcNo',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> mrcNoStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'mrcNo',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> mrcNoEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'mrcNo',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> mrcNoContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'mrcNo',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> mrcNoMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'mrcNo',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> mrcNoIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'mrcNo',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      mrcNoIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'mrcNo',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      paperWidthMmEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'paperWidthMm',
        value: value,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      paperWidthMmGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'paperWidthMm',
        value: value,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      paperWidthMmLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'paperWidthMm',
        value: value,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      paperWidthMmBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'paperWidthMm',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> portEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'port',
        value: value,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> portGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'port',
        value: value,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> portLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'port',
        value: value,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> portBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'port',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      primarySectorEqualTo(CategorySector value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'primarySector',
        value: value,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      primarySectorGreaterThan(
    CategorySector value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'primarySector',
        value: value,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      primarySectorLessThan(
    CategorySector value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'primarySector',
        value: value,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      primarySectorBetween(
    CategorySector lower,
    CategorySector upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'primarySector',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      recoveryCodeHashIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'recoveryCodeHash',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      recoveryCodeHashIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'recoveryCodeHash',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      recoveryCodeHashEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'recoveryCodeHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      recoveryCodeHashGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'recoveryCodeHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      recoveryCodeHashLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'recoveryCodeHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      recoveryCodeHashBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'recoveryCodeHash',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      recoveryCodeHashStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'recoveryCodeHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      recoveryCodeHashEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'recoveryCodeHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      recoveryCodeHashContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'recoveryCodeHash',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      recoveryCodeHashMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'recoveryCodeHash',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      recoveryCodeHashIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'recoveryCodeHash',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      recoveryCodeHashIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'recoveryCodeHash',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> sdcIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'sdcId',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      sdcIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'sdcId',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> sdcIdEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sdcId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      sdcIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sdcId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> sdcIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sdcId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> sdcIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sdcId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> sdcIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'sdcId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> sdcIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'sdcId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> sdcIdContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sdcId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> sdcIdMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sdcId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> sdcIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sdcId',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      sdcIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sdcId',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      serverIpIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'serverIp',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      serverIpIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'serverIp',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> serverIpEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'serverIp',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      serverIpGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'serverIp',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      serverIpLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'serverIp',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> serverIpBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'serverIp',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      serverIpStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'serverIp',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      serverIpEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'serverIp',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      serverIpContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'serverIp',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> serverIpMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'serverIp',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      serverIpIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'serverIp',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      serverIpIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'serverIp',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> taxIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'taxId',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      taxIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'taxId',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> taxIdEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'taxId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      taxIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'taxId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> taxIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'taxId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> taxIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'taxId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> taxIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'taxId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> taxIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'taxId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> taxIdContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'taxId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> taxIdMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'taxId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> taxIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'taxId',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      taxIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'taxId',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> taxRateEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'taxRate',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      taxRateGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'taxRate',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> taxRateLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'taxRate',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> taxRateBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'taxRate',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      terminalNameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'terminalName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      terminalNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'terminalName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      terminalNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'terminalName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      terminalNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'terminalName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      terminalNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'terminalName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      terminalNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'terminalName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      terminalNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'terminalName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      terminalNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'terminalName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      terminalNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'terminalName',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      terminalNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'terminalName',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> tpinIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'tpin',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      tpinIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'tpin',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> tpinEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'tpin',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> tpinGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'tpin',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> tpinLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'tpin',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> tpinBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'tpin',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> tpinStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'tpin',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> tpinEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'tpin',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> tpinContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'tpin',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> tpinMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'tpin',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> tpinIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'tpin',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      tpinIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'tpin',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      websiteIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'website',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      websiteIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'website',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> websiteEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'website',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      websiteGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'website',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> websiteLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'website',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> websiteBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'website',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      websiteStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'website',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> websiteEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'website',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> websiteContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'website',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition> websiteMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'website',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      websiteIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'website',
        value: '',
      ));
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterFilterCondition>
      websiteIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'website',
        value: '',
      ));
    });
  }
}

extension StoreConfigQueryObject
    on QueryBuilder<StoreConfig, StoreConfig, QFilterCondition> {}

extension StoreConfigQueryLinks
    on QueryBuilder<StoreConfig, StoreConfig, QFilterCondition> {}

extension StoreConfigQuerySortBy
    on QueryBuilder<StoreConfig, StoreConfig, QSortBy> {
  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByAddress() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'address', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByAddressDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'address', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByAutoPrintReceipt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'autoPrintReceipt', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByAutoPrintReceiptDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'autoPrintReceipt', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByBackupPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'backupPath', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByBackupPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'backupPath', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByBranchName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'branchName', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByBranchNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'branchName', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByBrandColorHex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'brandColorHex', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByBrandColorHexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'brandColorHex', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByBusinessName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'businessName', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByBusinessNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'businessName', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByContactNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contactNumber', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByContactNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contactNumber', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByCurrencySymbol() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'currencySymbol', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByCurrencySymbolDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'currencySymbol', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByDefaultPrinterAddress() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPrinterAddress', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByDefaultPrinterAddressDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPrinterAddress', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByDefaultPrinterModel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPrinterModel', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByDefaultPrinterModelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPrinterModel', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByDefaultPrinterName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPrinterName', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByDefaultPrinterNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPrinterName', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByDefaultPrinterType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPrinterType', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByDefaultPrinterTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPrinterType', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByEmail() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'email', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByEmailDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'email', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByIsManagerMode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isManagerMode', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByIsManagerModeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isManagerMode', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByLastBackupDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastBackupDate', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByLastBackupDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastBackupDate', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByLogoPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'logoPath', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByLogoPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'logoPath', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByLoyaltyEarnRate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'loyaltyEarnRate', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByLoyaltyEarnRateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'loyaltyEarnRate', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByLoyaltyEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'loyaltyEnabled', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByLoyaltyEnabledDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'loyaltyEnabled', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByLoyaltyRedemptionValue() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'loyaltyRedemptionValue', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByLoyaltyRedemptionValueDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'loyaltyRedemptionValue', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByMrcNo() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mrcNo', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByMrcNoDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mrcNo', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByPaperWidthMm() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'paperWidthMm', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByPaperWidthMmDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'paperWidthMm', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByPort() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'port', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByPortDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'port', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByPrimarySector() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'primarySector', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByPrimarySectorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'primarySector', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByRecoveryCodeHash() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'recoveryCodeHash', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByRecoveryCodeHashDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'recoveryCodeHash', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortBySdcId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sdcId', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortBySdcIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sdcId', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByServerIp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'serverIp', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByServerIpDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'serverIp', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByTaxId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'taxId', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByTaxIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'taxId', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByTaxRate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'taxRate', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByTaxRateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'taxRate', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByTerminalName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'terminalName', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      sortByTerminalNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'terminalName', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByTpin() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tpin', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByTpinDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tpin', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByWebsite() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'website', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> sortByWebsiteDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'website', Sort.desc);
    });
  }
}

extension StoreConfigQuerySortThenBy
    on QueryBuilder<StoreConfig, StoreConfig, QSortThenBy> {
  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByAddress() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'address', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByAddressDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'address', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByAutoPrintReceipt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'autoPrintReceipt', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByAutoPrintReceiptDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'autoPrintReceipt', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByBackupPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'backupPath', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByBackupPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'backupPath', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByBranchName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'branchName', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByBranchNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'branchName', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByBrandColorHex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'brandColorHex', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByBrandColorHexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'brandColorHex', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByBusinessName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'businessName', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByBusinessNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'businessName', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByContactNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contactNumber', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByContactNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contactNumber', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByCurrencySymbol() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'currencySymbol', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByCurrencySymbolDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'currencySymbol', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByDefaultPrinterAddress() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPrinterAddress', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByDefaultPrinterAddressDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPrinterAddress', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByDefaultPrinterModel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPrinterModel', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByDefaultPrinterModelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPrinterModel', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByDefaultPrinterName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPrinterName', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByDefaultPrinterNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPrinterName', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByDefaultPrinterType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPrinterType', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByDefaultPrinterTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'defaultPrinterType', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByEmail() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'email', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByEmailDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'email', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByIsManagerMode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isManagerMode', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByIsManagerModeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isManagerMode', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByLastBackupDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastBackupDate', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByLastBackupDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastBackupDate', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByLogoPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'logoPath', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByLogoPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'logoPath', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByLoyaltyEarnRate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'loyaltyEarnRate', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByLoyaltyEarnRateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'loyaltyEarnRate', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByLoyaltyEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'loyaltyEnabled', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByLoyaltyEnabledDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'loyaltyEnabled', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByLoyaltyRedemptionValue() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'loyaltyRedemptionValue', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByLoyaltyRedemptionValueDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'loyaltyRedemptionValue', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByMrcNo() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mrcNo', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByMrcNoDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mrcNo', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByPaperWidthMm() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'paperWidthMm', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByPaperWidthMmDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'paperWidthMm', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByPort() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'port', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByPortDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'port', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByPrimarySector() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'primarySector', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByPrimarySectorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'primarySector', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByRecoveryCodeHash() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'recoveryCodeHash', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByRecoveryCodeHashDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'recoveryCodeHash', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenBySdcId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sdcId', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenBySdcIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sdcId', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByServerIp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'serverIp', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByServerIpDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'serverIp', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByTaxId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'taxId', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByTaxIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'taxId', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByTaxRate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'taxRate', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByTaxRateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'taxRate', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByTerminalName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'terminalName', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy>
      thenByTerminalNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'terminalName', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByTpin() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tpin', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByTpinDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tpin', Sort.desc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByWebsite() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'website', Sort.asc);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QAfterSortBy> thenByWebsiteDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'website', Sort.desc);
    });
  }
}

extension StoreConfigQueryWhereDistinct
    on QueryBuilder<StoreConfig, StoreConfig, QDistinct> {
  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByAddress(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'address', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct>
      distinctByAutoPrintReceipt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'autoPrintReceipt');
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByBackupPath(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'backupPath', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByBranchName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'branchName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByBrandColorHex(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'brandColorHex',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByBusinessName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'businessName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByContactNumber(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'contactNumber',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByCurrencySymbol(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'currencySymbol',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct>
      distinctByDefaultPrinterAddress({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'defaultPrinterAddress',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct>
      distinctByDefaultPrinterModel({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'defaultPrinterModel',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct>
      distinctByDefaultPrinterName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'defaultPrinterName',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct>
      distinctByDefaultPrinterType({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'defaultPrinterType',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByEmail(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'email', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByIsManagerMode() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isManagerMode');
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByLastBackupDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastBackupDate');
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByLogoPath(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'logoPath', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct>
      distinctByLoyaltyEarnRate() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'loyaltyEarnRate');
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByLoyaltyEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'loyaltyEnabled');
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct>
      distinctByLoyaltyRedemptionValue() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'loyaltyRedemptionValue');
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByMrcNo(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mrcNo', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByPaperWidthMm() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'paperWidthMm');
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByPort() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'port');
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByPrimarySector() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'primarySector');
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByRecoveryCodeHash(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'recoveryCodeHash',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctBySdcId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sdcId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByServerIp(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'serverIp', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByTaxId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'taxId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByTaxRate() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'taxRate');
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByTerminalName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'terminalName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByTpin(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'tpin', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoreConfig, StoreConfig, QDistinct> distinctByWebsite(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'website', caseSensitive: caseSensitive);
    });
  }
}

extension StoreConfigQueryProperty
    on QueryBuilder<StoreConfig, StoreConfig, QQueryProperty> {
  QueryBuilder<StoreConfig, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<StoreConfig, String?, QQueryOperations> addressProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'address');
    });
  }

  QueryBuilder<StoreConfig, bool, QQueryOperations> autoPrintReceiptProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'autoPrintReceipt');
    });
  }

  QueryBuilder<StoreConfig, String?, QQueryOperations> backupPathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'backupPath');
    });
  }

  QueryBuilder<StoreConfig, String?, QQueryOperations> branchNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'branchName');
    });
  }

  QueryBuilder<StoreConfig, String?, QQueryOperations> brandColorHexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'brandColorHex');
    });
  }

  QueryBuilder<StoreConfig, String, QQueryOperations> businessNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'businessName');
    });
  }

  QueryBuilder<StoreConfig, String?, QQueryOperations> contactNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'contactNumber');
    });
  }

  QueryBuilder<StoreConfig, String?, QQueryOperations>
      currencySymbolProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'currencySymbol');
    });
  }

  QueryBuilder<StoreConfig, String?, QQueryOperations>
      defaultPrinterAddressProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'defaultPrinterAddress');
    });
  }

  QueryBuilder<StoreConfig, String?, QQueryOperations>
      defaultPrinterModelProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'defaultPrinterModel');
    });
  }

  QueryBuilder<StoreConfig, String?, QQueryOperations>
      defaultPrinterNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'defaultPrinterName');
    });
  }

  QueryBuilder<StoreConfig, String?, QQueryOperations>
      defaultPrinterTypeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'defaultPrinterType');
    });
  }

  QueryBuilder<StoreConfig, String?, QQueryOperations> emailProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'email');
    });
  }

  QueryBuilder<StoreConfig, bool, QQueryOperations> isManagerModeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isManagerMode');
    });
  }

  QueryBuilder<StoreConfig, DateTime?, QQueryOperations>
      lastBackupDateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastBackupDate');
    });
  }

  QueryBuilder<StoreConfig, String?, QQueryOperations> logoPathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'logoPath');
    });
  }

  QueryBuilder<StoreConfig, double, QQueryOperations>
      loyaltyEarnRateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'loyaltyEarnRate');
    });
  }

  QueryBuilder<StoreConfig, bool, QQueryOperations> loyaltyEnabledProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'loyaltyEnabled');
    });
  }

  QueryBuilder<StoreConfig, double, QQueryOperations>
      loyaltyRedemptionValueProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'loyaltyRedemptionValue');
    });
  }

  QueryBuilder<StoreConfig, String?, QQueryOperations> mrcNoProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mrcNo');
    });
  }

  QueryBuilder<StoreConfig, int, QQueryOperations> paperWidthMmProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'paperWidthMm');
    });
  }

  QueryBuilder<StoreConfig, int, QQueryOperations> portProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'port');
    });
  }

  QueryBuilder<StoreConfig, CategorySector, QQueryOperations>
      primarySectorProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'primarySector');
    });
  }

  QueryBuilder<StoreConfig, String?, QQueryOperations>
      recoveryCodeHashProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'recoveryCodeHash');
    });
  }

  QueryBuilder<StoreConfig, String?, QQueryOperations> sdcIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sdcId');
    });
  }

  QueryBuilder<StoreConfig, String?, QQueryOperations> serverIpProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'serverIp');
    });
  }

  QueryBuilder<StoreConfig, String?, QQueryOperations> taxIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'taxId');
    });
  }

  QueryBuilder<StoreConfig, double, QQueryOperations> taxRateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'taxRate');
    });
  }

  QueryBuilder<StoreConfig, String, QQueryOperations> terminalNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'terminalName');
    });
  }

  QueryBuilder<StoreConfig, String?, QQueryOperations> tpinProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'tpin');
    });
  }

  QueryBuilder<StoreConfig, String?, QQueryOperations> websiteProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'website');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetCustomerCollection on Isar {
  IsarCollection<Customer> get customers => this.collection();
}

const CustomerSchema = CollectionSchema(
  name: r'Customer',
  id: -7623823084711604343,
  properties: {
    r'accumulatedPoints': PropertySchema(
      id: 0,
      name: r'accumulatedPoints',
      type: IsarType.long,
    ),
    r'createdAt': PropertySchema(
      id: 1,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'email': PropertySchema(
      id: 2,
      name: r'email',
      type: IsarType.string,
    ),
    r'name': PropertySchema(
      id: 3,
      name: r'name',
      type: IsarType.string,
    ),
    r'phoneNumber': PropertySchema(
      id: 4,
      name: r'phoneNumber',
      type: IsarType.string,
    ),
    r'totalSpend': PropertySchema(
      id: 5,
      name: r'totalSpend',
      type: IsarType.double,
    )
  },
  estimateSize: _customerEstimateSize,
  serialize: _customerSerialize,
  deserialize: _customerDeserialize,
  deserializeProp: _customerDeserializeProp,
  idName: r'id',
  indexes: {
    r'phoneNumber': IndexSchema(
      id: 5414128966131364535,
      name: r'phoneNumber',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'phoneNumber',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _customerGetId,
  getLinks: _customerGetLinks,
  attach: _customerAttach,
  version: '3.1.0+1',
);

int _customerEstimateSize(
  Customer object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.email;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.name.length * 3;
  bytesCount += 3 + object.phoneNumber.length * 3;
  return bytesCount;
}

void _customerSerialize(
  Customer object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.accumulatedPoints);
  writer.writeDateTime(offsets[1], object.createdAt);
  writer.writeString(offsets[2], object.email);
  writer.writeString(offsets[3], object.name);
  writer.writeString(offsets[4], object.phoneNumber);
  writer.writeDouble(offsets[5], object.totalSpend);
}

Customer _customerDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = Customer(
    accumulatedPoints: reader.readLongOrNull(offsets[0]) ?? 0,
    createdAt: reader.readDateTimeOrNull(offsets[1]),
    email: reader.readStringOrNull(offsets[2]),
    id: id,
    name: reader.readString(offsets[3]),
    phoneNumber: reader.readString(offsets[4]),
    totalSpend: reader.readDoubleOrNull(offsets[5]) ?? 0.0,
  );
  return object;
}

P _customerDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLongOrNull(offset) ?? 0) as P;
    case 1:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 2:
      return (reader.readStringOrNull(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readDoubleOrNull(offset) ?? 0.0) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _customerGetId(Customer object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _customerGetLinks(Customer object) {
  return [];
}

void _customerAttach(IsarCollection<dynamic> col, Id id, Customer object) {
  object.id = id;
}

extension CustomerByIndex on IsarCollection<Customer> {
  Future<Customer?> getByPhoneNumber(String phoneNumber) {
    return getByIndex(r'phoneNumber', [phoneNumber]);
  }

  Customer? getByPhoneNumberSync(String phoneNumber) {
    return getByIndexSync(r'phoneNumber', [phoneNumber]);
  }

  Future<bool> deleteByPhoneNumber(String phoneNumber) {
    return deleteByIndex(r'phoneNumber', [phoneNumber]);
  }

  bool deleteByPhoneNumberSync(String phoneNumber) {
    return deleteByIndexSync(r'phoneNumber', [phoneNumber]);
  }

  Future<List<Customer?>> getAllByPhoneNumber(List<String> phoneNumberValues) {
    final values = phoneNumberValues.map((e) => [e]).toList();
    return getAllByIndex(r'phoneNumber', values);
  }

  List<Customer?> getAllByPhoneNumberSync(List<String> phoneNumberValues) {
    final values = phoneNumberValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'phoneNumber', values);
  }

  Future<int> deleteAllByPhoneNumber(List<String> phoneNumberValues) {
    final values = phoneNumberValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'phoneNumber', values);
  }

  int deleteAllByPhoneNumberSync(List<String> phoneNumberValues) {
    final values = phoneNumberValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'phoneNumber', values);
  }

  Future<Id> putByPhoneNumber(Customer object) {
    return putByIndex(r'phoneNumber', object);
  }

  Id putByPhoneNumberSync(Customer object, {bool saveLinks = true}) {
    return putByIndexSync(r'phoneNumber', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByPhoneNumber(List<Customer> objects) {
    return putAllByIndex(r'phoneNumber', objects);
  }

  List<Id> putAllByPhoneNumberSync(List<Customer> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'phoneNumber', objects, saveLinks: saveLinks);
  }
}

extension CustomerQueryWhereSort on QueryBuilder<Customer, Customer, QWhere> {
  QueryBuilder<Customer, Customer, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension CustomerQueryWhere on QueryBuilder<Customer, Customer, QWhereClause> {
  QueryBuilder<Customer, Customer, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<Customer, Customer, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<Customer, Customer, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<Customer, Customer, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterWhereClause> phoneNumberEqualTo(
      String phoneNumber) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'phoneNumber',
        value: [phoneNumber],
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterWhereClause> phoneNumberNotEqualTo(
      String phoneNumber) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'phoneNumber',
              lower: [],
              upper: [phoneNumber],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'phoneNumber',
              lower: [phoneNumber],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'phoneNumber',
              lower: [phoneNumber],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'phoneNumber',
              lower: [],
              upper: [phoneNumber],
              includeUpper: false,
            ));
      }
    });
  }
}

extension CustomerQueryFilter
    on QueryBuilder<Customer, Customer, QFilterCondition> {
  QueryBuilder<Customer, Customer, QAfterFilterCondition>
      accumulatedPointsEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'accumulatedPoints',
        value: value,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition>
      accumulatedPointsGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'accumulatedPoints',
        value: value,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition>
      accumulatedPointsLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'accumulatedPoints',
        value: value,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition>
      accumulatedPointsBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'accumulatedPoints',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> createdAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'createdAt',
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> createdAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'createdAt',
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> createdAtEqualTo(
      DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> createdAtGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> createdAtLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> createdAtBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'createdAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> emailIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'email',
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> emailIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'email',
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> emailEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'email',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> emailGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'email',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> emailLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'email',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> emailBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'email',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> emailStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'email',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> emailEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'email',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> emailContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'email',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> emailMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'email',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> emailIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'email',
        value: '',
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> emailIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'email',
        value: '',
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'name',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> nameContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> nameMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> phoneNumberEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'phoneNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition>
      phoneNumberGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'phoneNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> phoneNumberLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'phoneNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> phoneNumberBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'phoneNumber',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> phoneNumberStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'phoneNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> phoneNumberEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'phoneNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> phoneNumberContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'phoneNumber',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> phoneNumberMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'phoneNumber',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> phoneNumberIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'phoneNumber',
        value: '',
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition>
      phoneNumberIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'phoneNumber',
        value: '',
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> totalSpendEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'totalSpend',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> totalSpendGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'totalSpend',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> totalSpendLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'totalSpend',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Customer, Customer, QAfterFilterCondition> totalSpendBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'totalSpend',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }
}

extension CustomerQueryObject
    on QueryBuilder<Customer, Customer, QFilterCondition> {}

extension CustomerQueryLinks
    on QueryBuilder<Customer, Customer, QFilterCondition> {}

extension CustomerQuerySortBy on QueryBuilder<Customer, Customer, QSortBy> {
  QueryBuilder<Customer, Customer, QAfterSortBy> sortByAccumulatedPoints() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accumulatedPoints', Sort.asc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> sortByAccumulatedPointsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accumulatedPoints', Sort.desc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> sortByEmail() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'email', Sort.asc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> sortByEmailDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'email', Sort.desc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> sortByPhoneNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'phoneNumber', Sort.asc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> sortByPhoneNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'phoneNumber', Sort.desc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> sortByTotalSpend() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalSpend', Sort.asc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> sortByTotalSpendDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalSpend', Sort.desc);
    });
  }
}

extension CustomerQuerySortThenBy
    on QueryBuilder<Customer, Customer, QSortThenBy> {
  QueryBuilder<Customer, Customer, QAfterSortBy> thenByAccumulatedPoints() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accumulatedPoints', Sort.asc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> thenByAccumulatedPointsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accumulatedPoints', Sort.desc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> thenByEmail() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'email', Sort.asc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> thenByEmailDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'email', Sort.desc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> thenByPhoneNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'phoneNumber', Sort.asc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> thenByPhoneNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'phoneNumber', Sort.desc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> thenByTotalSpend() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalSpend', Sort.asc);
    });
  }

  QueryBuilder<Customer, Customer, QAfterSortBy> thenByTotalSpendDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalSpend', Sort.desc);
    });
  }
}

extension CustomerQueryWhereDistinct
    on QueryBuilder<Customer, Customer, QDistinct> {
  QueryBuilder<Customer, Customer, QDistinct> distinctByAccumulatedPoints() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'accumulatedPoints');
    });
  }

  QueryBuilder<Customer, Customer, QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<Customer, Customer, QDistinct> distinctByEmail(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'email', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Customer, Customer, QDistinct> distinctByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Customer, Customer, QDistinct> distinctByPhoneNumber(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'phoneNumber', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Customer, Customer, QDistinct> distinctByTotalSpend() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'totalSpend');
    });
  }
}

extension CustomerQueryProperty
    on QueryBuilder<Customer, Customer, QQueryProperty> {
  QueryBuilder<Customer, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<Customer, int, QQueryOperations> accumulatedPointsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'accumulatedPoints');
    });
  }

  QueryBuilder<Customer, DateTime?, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<Customer, String?, QQueryOperations> emailProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'email');
    });
  }

  QueryBuilder<Customer, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<Customer, String, QQueryOperations> phoneNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'phoneNumber');
    });
  }

  QueryBuilder<Customer, double, QQueryOperations> totalSpendProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'totalSpend');
    });
  }
}
