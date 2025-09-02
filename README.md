# MyArea Flutter App

A Flutter application for discovering and sharing local events and places.

## Features

- Location-based event discovery
- User authentication with Supabase
- Real-time messaging
- Map integration with Mapbox
- Push notifications
- Social features (friends, sharing)

## Prerequisites

- Flutter SDK (>=3.0.0)
- Dart SDK (>=3.0.0)
- Android Studio / Xcode for mobile development
- Supabase account
- Mapbox account

## Setup Instructions

### 1. Clone the Repository
```bash
git clone <repository-url>
cd myarea_app
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Environment Configuration

Create a `.env` file in the root directory with the following variables:

```env
SUPABASE_URL=your_supabase_project_url
SUPABASE_ANON_KEY=your_supabase_anon_key
GOOGLE_MAPS_API_KEY=your_google_maps_api_key
FIREBASE_API_KEY=your_firebase_api_key
FIREBASE_APP_ID=your_firebase_app_id
FIREBASE_SENDER_ID=your_firebase_sender_id
FIREBASE_PROJECT_ID=your_firebase_project_id
FIREBASE_STORAGE_BUCKET=your_firebase_storage_bucket
```

**Important:** You'll need access to the Supabase database. Contact the project owner to:
1. Get added as a collaborator to the Supabase project, OR
2. Get the database schema to set up your own development database

### 4. Database Setup Options

#### Option A: Use Shared Database (Recommended)
- Ask the project owner to add you as a collaborator in Supabase
- Use the provided Supabase URL and anon key
- You'll have access to real data for development

#### Option B: Create Your Own Database
- Create a new Supabase project
- Import the database schema (ask the project owner for schema export)
- Use your own Supabase credentials
- Note: You'll need to populate with test data

### 5. API Keys Configuration

#### Mapbox Token
Replace `YOUR_MAPBOX_TOKEN_HERE` in the following files with your actual Mapbox public token:

- `android/app/src/main/AndroidManifest.xml` (line 67)
- `ios/Runner/Info.plist` (line 75)

#### Firebase Configuration (if using Firebase features)
- Add your `google-services.json` to `android/app/`
- Add your `GoogleService-Info.plist` to `ios/Runner/`

### 6. Supabase Setup

1. Create a new Supabase project
2. Set up authentication providers (Google, Apple, etc.)
3. Configure your database schema
4. Update the Supabase URL and keys in your `.env` file

### 7. Run the App

```bash
# For development with environment variables
flutter run --dart-define=FIREBASE_API_KEY=your_firebase_api_key --dart-define=FIREBASE_APP_ID=your_firebase_app_id --dart-define=FIREBASE_SENDER_ID=your_firebase_sender_id --dart-define=FIREBASE_PROJECT_ID=your_firebase_project_id --dart-define=FIREBASE_STORAGE_BUCKET=your_firebase_storage_bucket

# For specific platforms
flutter run -d android
flutter run -d ios
```

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── models/                   # Data models
├── providers/                # State management
├── screens/                  # UI screens
│   ├── auth/                # Authentication screens
│   ├── events/              # Event-related screens
│   ├── friends/             # Social features
│   ├── messages/            # Messaging screens
│   └── profile/             # User profile screens
├── services/                # Business logic and API calls
├── styles/                  # App styling and colors
└── widgets/                 # Reusable UI components
```

## Dependencies

Key dependencies include:
- `supabase_flutter`: Backend and authentication
- `mapbox_maps_flutter`: Map functionality
- `provider`: State management
- `geolocator`: Location services
- `firebase_messaging`: Push notifications

## Development Notes

- The app uses Supabase for backend services
- Mapbox is used for map functionality
- Firebase is used for push notifications
- The app supports both Android and iOS platforms

## Troubleshooting

### Common Issues

1. **Build errors**: Make sure all dependencies are installed with `flutter pub get`
2. **API key errors**: Verify all API keys are correctly configured
3. **Location permissions**: Ensure location permissions are properly set up in both Android and iOS

### Getting Help

If you encounter issues:
1. Check the Flutter documentation
2. Review the Supabase documentation
3. Check the Mapbox documentation for map-related issues

## License

[Add your license information here]
