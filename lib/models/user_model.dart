class User {
  final String? id;
  final String email;
  final String username;
  final String? firstName;
  final String? lastName;
  final String? postcode;
  final String? ageGroup;
  final List<String>? interests;
  final String? appleUserId;
  
  User({
    this.id,
    required this.email,
    required this.username,
    this.firstName,
    this.lastName,
    this.postcode,
    this.ageGroup,
    this.interests,
    this.appleUserId,
  });
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'first_name': firstName,
      'last_name': lastName,
      'postcode': postcode,
      'age_group': ageGroup,
      'interests': interests,
      'apple_user_id': appleUserId,
    };
  }
  
  static User fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id']?.toString(),
      email: map['email'],
      username: map['username'] ?? '',
      firstName: map['first_name'],
      lastName: map['last_name'],
      postcode: map['postcode'],
      ageGroup: map['age_group'],
      interests: map['interests'] != null 
          ? List<String>.from(map['interests'])
          : null,
      appleUserId: map['apple_user_id'],
    );
  }
} 