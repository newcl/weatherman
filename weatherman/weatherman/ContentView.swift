//
//  ContentView.swift
//  weatherman
//
//  Created by Liang Chen on 2025-06-11.
//

import SwiftUI
import MapKit

// MARK: - Models
struct WeatherData: Codable {
    let main: MainWeather
    let weather: [Weather]
    let wind: Wind
    let coord: Coordinates
    
    struct MainWeather: Codable {
        let temp: Double
        let humidity: Int
        let feels_like: Double
    }
    
    struct Weather: Codable {
        let description: String
        let icon: String
    }
    
    struct Wind: Codable {
        let speed: Double
        let deg: Int
    }
    
    struct Coordinates: Codable {
        let lat: Double
        let lon: Double
    }
}

struct EnvironmentCanadaAlert: Codable {
    let type: String
    let properties: Properties
    let geometry: Geometry
    
    struct Properties: Codable {
        let title: String
        let description: String
        let severity: String
        let urgency: String
        let areas: String
        let effective: String
        let expires: String
    }
    
    struct Geometry: Codable {
        let type: String
        let coordinates: [[[Double]]]
    }
    
    var coordinate: CLLocationCoordinate2D? {
        guard let firstPolygon = geometry.coordinates.first,
              let firstPoint = firstPolygon.first else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: firstPoint[1], longitude: firstPoint[0])
    }
}

// Updated BC Wildfire Models
struct BCWildfireResponse: Codable {
    let features: [BCWildfireFeature]
}

struct BCWildfireFeature: Codable {
    let attributes: BCWildfireAttributes
    let geometry: BCWildfireGeometry
}

struct BCWildfireAttributes: Codable {
    let FIRE_NUMBER: String?
    let FIRE_STATUS: String?
    let FIRE_TYPE: String?
    let FIRE_CAUSE: String?
    let FIRE_SIZE_HECTARES: Double?
    let DISCOVERY_DATE: String?
    let FIRE_YEAR: Int?
    let RESPONSE_TYPE_DESC: String?
    let FIRE_LOCATION_NAME: String?
}

struct BCWildfireGeometry: Codable {
    let x: Double
    let y: Double
}

struct FireData: Codable, Identifiable {
    let id: String
    let latitude: Double
    let longitude: Double
    let confidence: Int
    let date: String
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct AlertItem: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let type: AlertType
    let description: String
    let source: String
    
    enum AlertType {
        case fire
        case thunder
        case other
    }
}

// Helper for decoding any JSON value
struct AnyCodable: Codable {
    let value: Any
    
    init<T>(_ value: T) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Cannot decode value")
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Cannot encode value")
            )
        }
    }
}

struct GeoJSONResponse: Codable {
    let type: String
    let features: [GeoJSONFeature]
}

struct GeoJSONFeature: Codable {
    let type: String
    let id: String
    let properties: GeoJSONProperties
    let geometry: GeoJSONGeometry
    
    var coordinate: CLLocationCoordinate2D? {
        switch geometry.type {
        case "Point":
            if let coordinates = geometry.coordinates.value as? [Double],
               coordinates.count >= 2 {
                return CLLocationCoordinate2D(latitude: coordinates[1], longitude: coordinates[0])
            }
        default:
            break
        }
        return nil
    }
}

struct GeoJSONProperties: Codable {
    let FIRE_NUMBER: String
    let FIRE_YEAR: Int
    let RESPONSE_TYPE_DESC: String?
    let IGNITION_DATE: String
    let FIRE_OUT_DATE: String?
    let FIRE_STATUS: String
    let FIRE_CAUSE: String
    let FIRE_TYPE: String
    let INCIDENT_NAME: String
    let GEOGRAPHIC_DESCRIPTION: String
    let CURRENT_SIZE: Double
    let FIRE_URL: String
    let SE_ANNO_CAD_DATA: String?
}

struct GeoJSONGeometry: Codable {
    let type: String
    let coordinates: AnyCodable
}

// MARK: - Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var locationManager = CLLocationManager()
    @Published var userLocation: CLLocationCoordinate2D?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.userLocation = location.coordinate
        }
    }
}

// MARK: - View Model
class WeatherViewModel: ObservableObject {
    @Published var weatherData: WeatherData?
    @Published var alertItems: [AlertItem] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let openWeatherAPIKey = "9a2f87aea6cd7d6dd1264297b7ac891a"
    
    func fetchWeatherData(latitude: Double, longitude: Double) async {
        await MainActor.run {
            self.alertItems.removeAll()
            self.isLoading = true
        }
        
        await fetchEnvironmentCanadaAlerts(latitude: latitude, longitude: longitude)
        await fetchBCWildfireData(latitude: latitude, longitude: longitude)
        await fetchCurrentWeather(latitude: latitude, longitude: longitude)
        
        await MainActor.run {
            self.isLoading = false
        }
    }
    
    private func fetchEnvironmentCanadaAlerts(latitude: Double, longitude: Double) async {
        let urlString = "https://weather.gc.ca/rss/warning/bc-48_e.xml"
        
        guard let url = URL(string: urlString) else {
            print("Invalid Environment Canada URL")
            return
        }
        
        do {
            let (data, httpResponse) = try await URLSession.shared.data(from: url)
            if let httpResponse = httpResponse as? HTTPURLResponse {
                print("Environment Canada API response status: \(httpResponse.statusCode)")
            }
            
            if let xmlString = String(data: data, encoding: .utf8) {
                let alertItems = xmlString.components(separatedBy: "<item>")
                    .filter { $0.contains("<title>") && $0.contains("<description>") }
                    .compactMap { item -> AlertItem? in
                        guard let titleRange = item.range(of: "<title>"),
                              let titleEndRange = item.range(of: "</title>"),
                              let descRange = item.range(of: "<description>"),
                              let descEndRange = item.range(of: "</description>") else {
                            return nil
                        }
                        
                        let title = String(item[titleRange.upperBound..<titleEndRange.lowerBound])
                        let description = String(item[descRange.upperBound..<descEndRange.lowerBound])
                        
                        let type: AlertItem.AlertType
                        if title.lowercased().contains("thunder") {
                            type = .thunder
                        } else if title.lowercased().contains("fire") {
                            type = .fire
                        } else {
                            type = .other
                        }
                        
                        return AlertItem(
                            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                            type: type,
                            description: "\(title): \(description)",
                            source: "Environment Canada"
                        )
                    }
                
                await MainActor.run {
                    self.alertItems.append(contentsOf: alertItems)
                }
            }
        } catch {
            print("Environment Canada API error: \(error)")
        }
    }
    
    private func fetchBCWildfireData(latitude: Double, longitude: Double) async {
        // Official BC Government wildfire data endpoint
        let baseUrl = "https://services6.arcgis.com/ubm4tcTYICKBpist/arcgis/rest/services/BCWS_FireLocations_PublicView/FeatureServer/0/query"
        
        let queryItems = [
            URLQueryItem(name: "where", value: "FIRE_STATUS IN ('Out of Control', 'Holding', 'Under Control', 'Out')"),
            URLQueryItem(name: "outFields", value: "FIRE_NUMBER,FIRE_STATUS,FIRE_TYPE,FIRE_CAUSE,FIRE_SIZE_HECTARES,DISCOVERY_DATE,FIRE_YEAR,RESPONSE_TYPE_DESC,FIRE_LOCATION_NAME"),
            URLQueryItem(name: "geometryType", value: "esriGeometryPoint"),
            URLQueryItem(name: "spatialRel", value: "esriSpatialRelWithin"),
            URLQueryItem(name: "geometry", value: String(format: "{\"x\":%.6f,\"y\":%.6f}", longitude, latitude)),
            URLQueryItem(name: "distance", value: "100000"),
            URLQueryItem(name: "units", value: "esriSRUnit_Meter"),
            URLQueryItem(name: "inSR", value: "4326"),
            URLQueryItem(name: "outSR", value: "4326"),
            URLQueryItem(name: "f", value: "json"),
            URLQueryItem(name: "returnGeometry", value: "true")
        ]
        
        var urlComponents = URLComponents(string: baseUrl)!
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else {
            print("Invalid BC Wildfire URL")
            return
        }
        
        print("BC Wildfire API URL: \(url)")
        
        do {
            let (data, httpResponse) = try await URLSession.shared.data(from: url)
            if let httpResponse = httpResponse as? HTTPURLResponse {
                print("BC Wildfire API response status: \(httpResponse.statusCode)")
            }
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("BC Wildfire API Response: \(responseString)")
            }
            
            let wildfireResponse = try JSONDecoder().decode(BCWildfireResponse.self, from: data)
            
            await MainActor.run {
                let newAlerts = wildfireResponse.features.compactMap { feature -> AlertItem? in
                    guard let fireNumber = feature.attributes.FIRE_NUMBER,
                          let fireStatus = feature.attributes.FIRE_STATUS else {
                        return nil
                    }
                    
                    let fireSize = feature.attributes.FIRE_SIZE_HECTARES ?? 0.0
                    let fireType = feature.attributes.FIRE_TYPE ?? "Unknown"
                    let fireLocation = feature.attributes.FIRE_LOCATION_NAME ?? "Unknown Location"
                    
                    let description = """
                    Fire #\(fireNumber) - \(fireStatus)
                    Location: \(fireLocation)
                    Type: \(fireType)
                    Size: \(String(format: "%.1f", fireSize)) hectares
                    """
                    
                    return AlertItem(
                        coordinate: CLLocationCoordinate2D(
                            latitude: feature.geometry.y,
                            longitude: feature.geometry.x
                        ),
                        type: .fire,
                        description: description,
                        source: "BC Wildfire Service"
                    )
                }
                
                print("Found \(newAlerts.count) active wildfires")
                self.alertItems.append(contentsOf: newAlerts)
            }
            
        } catch {
            print("BC Wildfire API error: \(error)")
            await fetchBCWildfireDataAlternative(latitude: latitude, longitude: longitude)
        }
    }
    
    private func fetchBCWildfireDataAlternative(latitude: Double, longitude: Double) async {
        let baseUrl = "https://openmaps.gov.bc.ca/geo/pub/WHSE_LAND_AND_NATURAL_RESOURCE.PROT_CURRENT_FIRE_PNTS_SP/ows"
        
        let queryItems = [
            URLQueryItem(name: "service", value: "WFS"),
            URLQueryItem(name: "version", value: "2.0.0"),
            URLQueryItem(name: "request", value: "GetFeature"),
            URLQueryItem(name: "typeName", value: "WHSE_LAND_AND_NATURAL_RESOURCE.PROT_CURRENT_FIRE_PNTS_SP"),
            URLQueryItem(name: "outputFormat", value: "application/json"),
            URLQueryItem(name: "srsName", value: "EPSG:4326"),
            URLQueryItem(name: "bbox", value: String(format: "%.6f,%.6f,%.6f,%.6f,EPSG:4326", 
                                                   longitude - 1.0, latitude - 1.0, 
                                                   longitude + 1.0, latitude + 1.0))
        ]
        
        var urlComponents = URLComponents(string: baseUrl)!
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else {
            print("Invalid BC Wildfire alternative URL")
            return
        }
        
        print("BC Wildfire Alternative API URL: \(url)")
        
        do {
            let (data, httpResponse) = try await URLSession.shared.data(from: url)
            if let httpResponse = httpResponse as? HTTPURLResponse {
                print("BC Wildfire alternative API response status: \(httpResponse.statusCode)")
            }
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("BC Wildfire Alternative API Response: \(responseString)")
            }
            
            let geoJsonResponse = try JSONDecoder().decode(GeoJSONResponse.self, from: data)
            
            await MainActor.run {
                let newAlerts = geoJsonResponse.features.compactMap { feature -> AlertItem? in
                    guard let coordinate = feature.coordinate else {
                        return nil
                    }
                    
                    let description = """
                    Fire #\(feature.properties.FIRE_NUMBER) - \(feature.properties.FIRE_STATUS)
                    Location: \(feature.properties.GEOGRAPHIC_DESCRIPTION)
                    Type: \(feature.properties.FIRE_TYPE)
                    Size: \(String(format: "%.1f", feature.properties.CURRENT_SIZE)) hectares
                    """
                    
                    return AlertItem(
                        coordinate: coordinate,
                        type: .fire,
                        description: description,
                        source: "BC Government Data"
                    )
                }
                
                print("Found \(newAlerts.count) active wildfires from alternative source")
                self.alertItems.append(contentsOf: newAlerts)
            }
        } catch {
            print("BC Wildfire alternative API error: \(error)")
        }
    }
    
    private func fetchCurrentWeather(latitude: Double, longitude: Double) async {
        let urlString = "https://api.openweathermap.org/data/2.5/weather?lat=\(latitude)&lon=\(longitude)&units=metric&appid=\(openWeatherAPIKey)"
        
        guard let url = URL(string: urlString) else {
            print("Invalid weather URL")
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let weather = try JSONDecoder().decode(WeatherData.self, from: data)
            
            await MainActor.run {
                self.weatherData = weather
                self.error = nil
                
                var alerts: [AlertItem] = []
                
                if weather.weather.contains(where: { $0.description.lowercased().contains("thunder") }) {
                    alerts.append(AlertItem(
                        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                        type: .thunder,
                        description: "Thunderstorm conditions detected",
                        source: "Current Weather"
                    ))
                }
                
                if weather.wind.speed > 20 {
                    alerts.append(AlertItem(
                        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                        type: .other,
                        description: "High wind conditions: \(Int(weather.wind.speed)) m/s",
                        source: "Current Weather"
                    ))
                }
                
                if weather.main.temp > 25 && weather.wind.speed > 10 && weather.main.humidity < 30 {
                    alerts.append(AlertItem(
                        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                        type: .fire,
                        description: "High fire risk conditions: High temperature, low humidity, and strong winds",
                        source: "Weather Conditions"
                    ))
                }
                
                self.alertItems.append(contentsOf: alerts)
            }
        } catch {
            print("Weather API error: \(error)")
            await MainActor.run {
                if let decodingError = error as? DecodingError {
                    self.error = "Error parsing weather data. Please try again later."
                } else {
                    self.error = "Failed to fetch weather data: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Main View
struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var weatherViewModel = WeatherViewModel()
    @State private var hasInitialLocation = false
    @State private var isWeatherExpanded = true
    @State private var isAlertsExpanded = true

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )

    var body: some View {
        ZStack {
            Map(coordinateRegion: $region, showsUserLocation: true, annotationItems: annotationData) { item in
                MapAnnotation(coordinate: item.coordinate) {
                    switch item.type {
                    case .fire:
                        VStack {
                            Image(systemName: "flame.fill")
                                .foregroundColor(isActiveFire(item) ? .red : .gray)
                                .font(.title)
                                .shadow(radius: 2)
                            Text(item.description.components(separatedBy: "\n").first ?? "")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.black.opacity(0.8))
                                .cornerRadius(4)
                        }
                    case .thunder:
                        Image(systemName: "cloud.bolt.fill")
                            .foregroundColor(.yellow)
                            .font(.title)
                            .shadow(radius: 2)
                    case .other:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.title)
                            .shadow(radius: 2)
                    }
                }
            }
            .edgesIgnoringSafeArea(.all)
            .onReceive(locationManager.$userLocation) { location in
                if let location = location {
                    if !hasInitialLocation {
                        hasInitialLocation = true
                        region.center = location
                        Task {
                            print("Fetching initial weather data...")
                            await weatherViewModel.fetchWeatherData(latitude: location.latitude, longitude: location.longitude)
                        }
                    }
                }
            }
            
            VStack {
                if let weather = weatherViewModel.weatherData {
                    DisclosureGroup(
                        isExpanded: $isWeatherExpanded,
                        content: {
                            WeatherView(weather: weather)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(10)
                        },
                        label: {
                            HStack {
                                Image(systemName: "cloud.sun.fill")
                                Text("Weather Information")
                                Spacer()
                                Image(systemName: isWeatherExpanded ? "chevron.up" : "chevron.down")
                            }
                            .padding()
                            .background(Color.white)
                            .cornerRadius(10)
                        }
                    )
                    .padding(.horizontal)
                }
                
                if let error = weatherViewModel.error {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(10)
                        .padding()
                }
                
                if !weatherViewModel.alertItems.isEmpty {
                    DisclosureGroup(
                        isExpanded: $isAlertsExpanded,
                        content: {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(weatherViewModel.alertItems) { alert in
                                        CompactAlertView(alert: alert, isActive: isActiveFire(alert))
                                            .onTapGesture {
                                                if alert.type == .fire {
                                                    withAnimation {
                                                        region.center = alert.coordinate
                                                        region.span = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                                                    }
                                                }
                                            }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .frame(maxHeight: 200)
                            .background(Color.white)
                            .cornerRadius(10)
                        },
                        label: {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text("Alerts (\(weatherViewModel.alertItems.count))")
                                Spacer()
                                Image(systemName: isAlertsExpanded ? "chevron.up" : "chevron.down")
                            }
                            .padding()
                            .background(Color.white)
                            .cornerRadius(10)
                        }
                    )
                    .padding(.horizontal)
                }
                
                Spacer()
                
                HStack {
                    Spacer()
                    Button(action: {
                        if let location = locationManager.userLocation {
                            print("Recentering map and refreshing data...")
                            withAnimation {
                                region.center = location
                            }
                            Task {
                                await weatherViewModel.fetchWeatherData(latitude: location.latitude, longitude: location.longitude)
                            }
                        }
                    }) {
                        Image(systemName: "location.fill")
                            .padding()
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                    .padding()
                }
            }
        }
    }

    private func isActiveFire(_ alert: AlertItem) -> Bool {
        if alert.type == .fire {
            return alert.description.contains("Out of Control") || 
                   alert.description.contains("Holding") || 
                   alert.description.contains("Under Control")
        }
        return false
    }

    var annotationData: [AlertItem] {
        weatherViewModel.alertItems
    }
}

// MARK: - Supporting Views
struct WeatherView: View {
    let weather: WeatherData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Weather")
                .font(.headline)
                .foregroundColor(.black)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("\(Int(weather.main.temp))°C")
                        .font(.title)
                        .foregroundColor(.black)
                    Text(weather.weather.first?.description.capitalized ?? "")
                        .font(.subheadline)
                        .foregroundColor(.black)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Humidity: \(weather.main.humidity)%")
                        .foregroundColor(.black)
                    Text("Wind: \(Int(weather.wind.speed)) m/s")
                        .foregroundColor(.black)
                }
            }
        }
    }
}

struct CompactAlertView: View {
    let alert: AlertItem
    let isActive: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconName)
                .foregroundColor(isActive ? iconColor : .gray)
                .font(.system(size: 16))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.type == .fire ? "Fire Alert" : 
                     alert.type == .thunder ? "Thunderstorm Alert" : "Weather Alert")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                Text(alert.description)
                    .font(.caption)
                    .foregroundColor(.black)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Text(alert.source)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .padding(8)
        .background(Color.white)
        .cornerRadius(8)
        .contentShape(Rectangle())
    }
    
    private var iconName: String {
        switch alert.type {
        case .fire: return "flame.fill"
        case .thunder: return "cloud.bolt.fill"
        case .other: return "exclamationmark.triangle.fill"
        }
    }
    
    private var iconColor: Color {
        switch alert.type {
        case .fire: return .red
        case .thunder: return .yellow
        case .other: return .orange
        }
    }
}

#Preview {
    ContentView()
}