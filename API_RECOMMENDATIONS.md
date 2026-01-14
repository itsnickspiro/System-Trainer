# Comprehensive API Recommendations for RPT Fitness App

## Currently Integrated APIs ✅
- **API Ninjas** - Exercise, Nutrition, Recipe data
- **OpenAI ChatGPT** - AI coaching (currently disabled)
- **Firebase** - User authentication, cloud sync, leaderboard

---

## Priority 1: Essential for Beta (High Impact, Easy Integration)

### 1. **Nutritionix API**
**URL:** https://www.nutritionix.com/business/api
**Purpose:** Enhanced food tracking with extensive database
**Key Features:**
- 800,000+ foods including restaurant items
- Natural language food search ("2 eggs and toast")
- Barcode scanning support (better than current implementation)
- Macro and micronutrient breakdown
**Pricing:** Free tier (750 requests/day), Paid ($99/month unlimited)
**Integration Complexity:** Low (REST API, similar to current nutrition API)
**Benefits:** Significantly improves Diet tab accuracy and user experience

### 2. **Edamam Food Database API**
**URL:** https://www.edamam.com/
**Purpose:** Nutrition analysis and recipe search
**Key Features:**
- 900,000+ food items
- Recipe nutritional analysis
- Diet label classification (vegan, paleo, etc.)
- Allergen detection
**Pricing:** Free tier (5,000 requests/month), Developer ($49/month)
**Integration Complexity:** Low
**Benefits:** Better recipe recommendations aligned with user health goals

### 3. **Google Fit REST API**
**URL:** https://developers.google.com/fit
**Purpose:** Cross-platform health data sync (for Android users later)
**Key Features:**
- Activity tracking
- Sleep data
- Nutrition logging
- Works alongside HealthKit
**Pricing:** Free
**Integration Complexity:** Medium (OAuth required)
**Benefits:** Expands user base to Android when ready

---

## Priority 2: Enhanced Features (High Value Add)

### 4. **Strava API**
**URL:** https://developers.strava.com/
**Purpose:** Social fitness integration and workout tracking
**Key Features:**
- Detailed workout analytics
- Segment tracking (running/cycling routes)
- Social features (clubs, challenges)
- Achievement system
**Pricing:** Free (rate limits apply)
**Integration Complexity:** Medium (OAuth, webhooks available)
**Benefits:** Adds competitive element, appeals to serious athletes

### 5. **Fitbit Web API**
**URL:** https://dev.fitbit.com/build/reference/web-api/
**Purpose:** Import data from Fitbit devices
**Key Features:**
- Steps, heart rate, sleep data
- Active minutes tracking
- Food and water logging
**Pricing:** Free
**Integration Complexity:** Medium (OAuth required)
**Benefits:** Allows users with Fitbit devices to import their data automatically

### 6. **MyFitnessPal API** (Partner Integration)
**URL:** https://www.myfitnesspal.com/api
**Purpose:** World's largest food database
**Key Features:**
- 14+ million foods
- Restaurant menu items
- User-contributed recipes
- Barcode database
**Pricing:** Partnership required
**Integration Complexity:** High (requires business partnership)
**Benefits:** Industry-standard nutrition tracking

### 7. **Spoonacular API**
**URL:** https://spoonacular.com/food-api
**Purpose:** Advanced recipe and meal planning
**Key Features:**
- 5,000+ recipes with instructions
- Meal planning suggestions
- Shopping list generation
- Recipe video content
- Ingredient substitutions
**Pricing:** Free tier (150 requests/day), Paid ($49-$199/month)
**Integration Complexity:** Low (comprehensive REST API)
**Benefits:** Transforms Diet tab into full meal planning solution

---

## Priority 3: Gamification & Engagement

### 8. **OneSignal Push Notifications**
**URL:** https://onesignal.com/
**Purpose:** Smart push notifications
**Key Features:**
- Scheduled notifications
- In-app messaging
- User segmentation
- A/B testing
- Rich media notifications
**Pricing:** Free tier (unlimited notifications), Paid (advanced features)
**Integration Complexity:** Low (iOS SDK available)
**Benefits:** Critical for quest reminders, streak maintenance, level-up celebrations

### 9. **RevenueCat**
**URL:** https://www.revenuecat.com/
**Purpose:** In-app purchases and subscriptions
**Key Features:**
- Subscription management
- Paywall A/B testing
- Customer analytics
- Cross-platform support
**Pricing:** Free tier (up to $10k monthly revenue), 1% fee after
**Integration Complexity:** Low (SwiftUI SDK)
**Benefits:** Monetization ready when you add premium features

### 10. **Mixpanel Analytics**
**URL:** https://mixpanel.com/
**Purpose:** Advanced user analytics
**Key Features:**
- User behavior tracking
- Funnel analysis
- Cohort analysis
- Retention reports
**Pricing:** Free tier (100k events/month), Paid ($25+/month)
**Integration Complexity:** Low (iOS SDK)
**Benefits:** Understand user engagement, optimize retention

---

## Priority 4: Advanced Features (Future Enhancements)

### 11. **Withings API**
**URL:** https://developer.withings.com/
**Purpose:** Smart scale and health device integration
**Key Features:**
- Weight tracking
- Body composition (fat %, muscle mass)
- Blood pressure
- Sleep tracking
**Pricing:** Free
**Integration Complexity:** Medium (OAuth)
**Benefits:** Automatic weight and body composition tracking

### 12. **OpenWeather API**
**URL:** https://openweathermap.org/api
**Purpose:** Weather-based workout suggestions
**Key Features:**
- Current weather conditions
- 5-day forecast
- Air quality index
- UV index
**Pricing:** Free tier (1,000 requests/day), Paid ($40/month for more)
**Integration Complexity:** Very Low (simple REST API)
**Benefits:** Smart workout recommendations ("Rain expected, try indoor workout")

### 13. **Mapbox API**
**URL:** https://www.mapbox.com/
**Purpose:** Running/cycling route tracking and visualization
**Key Features:**
- Route mapping
- Elevation profiles
- Turn-by-turn directions
- Custom map styling
**Pricing:** Free tier (50,000 loads/month), Paid ($5/1,000 requests)
**Integration Complexity:** Medium (iOS SDK available)
**Benefits:** Visual workout tracking for outdoor activities

### 14. **YouTube Data API**
**URL:** https://developers.google.com/youtube/v3
**Purpose:** Workout video integration
**Key Features:**
- Search workout videos
- Playlist creation
- Video playback
- Channel data
**Pricing:** Free (10,000 quota units/day)
**Integration Complexity:** Low (REST API)
**Benefits:** In-app workout video tutorials

### 15. **Spotify Web API**
**URL:** https://developer.spotify.com/documentation/web-api
**Purpose:** Workout music integration
**Key Features:**
- Playlist access
- Music playback control
- Tempo-based song selection
- User's saved playlists
**Pricing:** Free
**Integration Complexity:** Medium (OAuth, iOS SDK available)
**Benefits:** Curated workout playlists, tempo-matched music

---

## Priority 5: Social & Community

### 16. **Stream Chat API**
**URL:** https://getstream.io/chat/
**Purpose:** In-app messaging and community features
**Key Features:**
- 1-on-1 and group chat
- Reactions and threads
- Push notifications
- Moderation tools
**Pricing:** Free tier (unlimited chat, 25 users), Paid ($99/month)
**Integration Complexity:** Medium (SwiftUI SDK)
**Benefits:** Build community, friend challenges, accountability partners

### 17. **Cloudinary**
**URL:** https://cloudinary.com/
**Purpose:** Image hosting for user progress photos
**Key Features:**
- Image upload and storage
- Automatic optimization
- Transformation API
- CDN delivery
**Pricing:** Free tier (25GB storage, 25GB bandwidth), Paid ($89+/month)
**Integration Complexity:** Low (iOS SDK)
**Benefits:** Before/after photo tracking, profile pictures

### 18. **Twilio SendGrid**
**URL:** https://sendgrid.com/
**Purpose:** Email notifications and newsletters
**Key Features:**
- Transactional emails
- Marketing campaigns
- Analytics
- Template system
**Pricing:** Free tier (100 emails/day), Paid ($19.95+/month)
**Integration Complexity:** Very Low (REST API)
**Benefits:** Weekly progress reports, achievement emails, re-engagement

---

## Priority 6: Health & Wellness Expansion

### 19. **OpenAI GPT-4 API** (Re-enable AI Coach)
**URL:** https://platform.openai.com/
**Purpose:** Intelligent fitness coaching
**Key Features:**
- Natural language understanding
- Personalized advice
- Workout plan generation
- Nutrition guidance
**Pricing:** $0.03/1K tokens (GPT-4), $0.002/1K tokens (GPT-3.5 Turbo)
**Integration Complexity:** Low (REST API, already partially implemented)
**Benefits:** Premium AI coaching feature, major differentiator

### 20. **Anthropic Claude API** (Alternative to OpenAI)
**URL:** https://www.anthropic.com/
**Purpose:** Alternative AI coaching with better safety
**Key Features:**
- Long context windows (100k+ tokens)
- Better at following instructions
- More factual health advice
- Constitutional AI (safer responses)
**Pricing:** Similar to OpenAI
**Integration Complexity:** Low (similar to OpenAI API)
**Benefits:** Better for health advice, fewer hallucinations

### 21. **Headspace for Organizations API**
**URL:** https://work.headspace.com/
**Purpose:** Meditation and mindfulness integration
**Key Features:**
- Guided meditations
- Sleep sounds
- Mindfulness exercises
- Progress tracking
**Pricing:** Partnership/Enterprise pricing
**Integration Complexity:** High (requires partnership)
**Benefits:** Complete wellness solution (physical + mental health)

### 22. **Cronometer API**
**URL:** https://cronometer.com/
**Purpose:** Micronutrient tracking
**Key Features:**
- Vitamin and mineral tracking
- Biometric tracking
- Custom foods
- Detailed nutrition database
**Pricing:** Free tier, Gold ($49.95/year)
**Integration Complexity:** Medium
**Benefits:** Advanced nutrition tracking for serious users

---

## Priority 7: Motivation & Content

### 23. **Giphy API**
**URL:** https://developers.giphy.com/
**Purpose:** Motivational GIFs and reactions
**Key Features:**
- Search GIFs
- Trending content
- Stickers
**Pricing:** Free (rate limits), Paid for production
**Integration Complexity:** Very Low (REST API)
**Benefits:** Fun celebrations for achievements, quest completions

### 24. **Unsplash API**
**URL:** https://unsplash.com/developers
**Purpose:** High-quality motivational images
**Key Features:**
- 3+ million free photos
- Search by keyword
- Random images
**Pricing:** Free (5,000 requests/hour)
**Integration Complexity:** Very Low (REST API)
**Benefits:** Beautiful backgrounds, recipe photos, workout inspiration

### 25. **Quotes API (ZenQuotes)**
**URL:** https://zenquotes.io/
**Purpose:** Daily motivational quotes
**Key Features:**
- Random quotes
- Author search
- Keyword search
**Pricing:** Free (5 requests/30 seconds)
**Integration Complexity:** Very Low (REST API)
**Benefits:** Daily motivation on home screen

---

## Recommended Implementation Order

### Phase 1: Beta Launch (Next 2-4 weeks)
1. **Nutritionix** - Better food tracking
2. **OneSignal** - Quest reminders and notifications
3. **Mixpanel** - Analytics for optimization

### Phase 2: Post-Beta (1-2 months)
4. **Spoonacular** - Enhanced meal planning
5. **Edamam** - Recipe analysis
6. **RevenueCat** - Monetization setup
7. **OpenWeather** - Weather-based suggestions

### Phase 3: Growth Features (2-4 months)
8. **OpenAI GPT-4** - Re-enable AI Coach as premium feature
9. **Strava** - Social fitness integration
10. **Stream Chat** - Community features
11. **Cloudinary** - Progress photos

### Phase 4: Advanced Platform (4-6 months)
12. **Fitbit & Withings** - Device integrations
13. **Google Fit** - Android preparation
14. **Mapbox** - Route tracking
15. **YouTube & Spotify** - Media integration

---

## Cost Estimate (Monthly)

### Minimum Viable (Beta):
- Nutritionix Free Tier: $0
- OneSignal Free Tier: $0
- Mixpanel Free Tier: $0
**Total: $0/month**

### Growth Phase:
- Nutritionix Paid: $99
- Spoonacular Paid: $49
- RevenueCat: 1% of revenue
- Mixpanel Growth: $25
- OneSignal Paid: $0-99
**Total: ~$200-300/month**

### Full Platform:
- All above APIs
- OpenAI GPT-4: ~$50-200 (usage based)
- Stream Chat: $99
- Cloudinary: $89
**Total: ~$500-700/month**

---

## Integration Priority by Feature

### Diet Tab Enhancement:
1. Nutritionix (HIGH)
2. Spoonacular (HIGH)
3. Edamam (MEDIUM)
4. OpenFoodFacts (already partially used)

### Training Tab Enhancement:
1. YouTube API (MEDIUM)
2. Spotify API (LOW - nice to have)

### Engagement & Retention:
1. OneSignal (HIGH)
2. Mixpanel (HIGH)
3. Giphy/ZenQuotes (LOW)

### Social Features:
1. Stream Chat (MEDIUM)
2. Strava (MEDIUM)

### Monetization:
1. RevenueCat (MEDIUM - set up early)

### Health Data:
1. Google Fit (MEDIUM - for Android)
2. Fitbit (LOW)
3. Withings (LOW)

---

## Notes

- **Start with free tiers** during beta testing
- **Monitor usage** to understand when to upgrade
- **Most APIs** have generous free tiers suitable for early growth
- **Consider user privacy** - always get consent for data sharing
- **API keys** should be stored securely (already using Secrets.swift)
- **Rate limiting** - implement retry logic and caching
- **Error handling** - gracefully fall back when APIs are unavailable

## Quick Wins for Beta

These can be implemented in 1-2 days each:
1. **ZenQuotes** - Daily motivation on home screen
2. **OpenWeather** - Smart workout suggestions
3. **Giphy** - Celebration animations
4. **Unsplash** - Beautiful recipe/workout images

## Contact for Partnerships

Some APIs require business partnerships:
- MyFitnessPal
- Headspace
- Peloton Digital (for class content)
- Apple Health Research (advanced HealthKit features)

Would recommend reaching out once you hit 1,000+ active users.
