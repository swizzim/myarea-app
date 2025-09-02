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
```

### 4. API Keys Configuration

#### Mapbox Token
Replace `YOUR_MAPBOX_TOKEN_HERE` in the following files with your actual Mapbox public token:

- `android/app/src/main/AndroidManifest.xml` (line 67)
- `ios/Runner/Info.plist` (line 75)

#### Firebase Configuration (if using Firebase features)
- Add your `google-services.json` to `android/app/`
- Add your `GoogleService-Info.plist` to `ios/Runner/`

### 5. Supabase Setup

1. Create a new Supabase project
2. Set up authentication providers (Google, Apple, etc.)
3. Configure your database schema
4. Update the Supabase URL and keys in your `.env` file

### 6. Run the App

```bash
# For development
flutter run

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
