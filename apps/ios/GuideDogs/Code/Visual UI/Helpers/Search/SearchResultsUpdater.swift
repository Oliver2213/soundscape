//
//  SearchResultsUpdater.swift
//  Openscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import Foundation
import CoreLocation

protocol SearchResultsUpdaterDelegate: AnyObject {
    func searchResultsDidStartUpdating()
    func searchResultsDidUpdate(_ searchResults: [POI], searchLocation: CLLocation?)
    func searchResultsDidUpdate(_ searchForMore: String?)
    func searchWasCancelled()
    var isPresentingDefaultResults: Bool { get }
    var telemetryContext: String { get }
    // Set `isCachingRequired = true` if a selected search result will
    // be cached on device
    // Search results can only be cached when an unencumbered coordinate is available
    var isCachingRequired: Bool { get }
}

class SearchResultsUpdater: NSObject {
    
    enum Context {
        case partialSearchText
        case completeSearchText
    }
    
    // MARK: Properties
    
    weak var delegate: SearchResultsUpdaterDelegate?
    private var searchRequestToken: RequestToken?
    private var searchResultsUpdating = false
    private(set) var searchBarButtonClicked = false
    private var location: CLLocation?
    var context: Context = .partialSearchText
    
    // MARK: Initialization
    
    override init() {
        super.init()
        
        // Save user's current location
        location = AppContext.shared.geolocationManager.location
        
        // Observe changes in user's location
        // This is required so that we can present all search
        // results with an accurate distance
        NotificationCenter.default.addObserver(self, selector: #selector(self.onLocationUpdated(_:)), name: Notification.Name.locationUpdated, object: nil)
    }
    
    deinit {
        searchRequestToken?.cancel()
    }
    
    // MARK: Notifications
    
    @objc
    private func onLocationUpdated(_ notification: Notification) {
        guard let location = notification.userInfo?[SpatialDataContext.Keys.location] as? CLLocation else {
            return
        }
        
        self.location = location
    }
    
    // MARK: Selecting Search Results
    
    func selectSearchResult(_ poi: POI, completion: @escaping (SearchResult?, SearchResultError?) -> Void) {
        if let delegate = delegate, delegate.isPresentingDefaultResults {
            GDATelemetry.track("recent_entity_selected.search", with: ["context": delegate.telemetryContext])
            completion(.entity(poi), nil)
        } else {
            completion(.entity(poi), nil)
        }
    }
    
}

// MARK: - UISearchResultsUpdating

extension SearchResultsUpdater: UISearchResultsUpdating {
    
    func updateSearchResults(for searchController: UISearchController) {
        searchBarButtonClicked = false
        
        if let searchBarText = searchController.searchBar.text, searchBarText.isEmpty == false {
            // Fetch new search results
            switch context {
            case .partialSearchText: partialSearchWithText(searchText: searchBarText)
            case .completeSearchText: searchWithText(searchText: searchBarText)
            }
        } else {
            searchResultsUpdating = false
            // There is no search text
            // Clear current search results
            delegate?.searchResultsDidUpdate([], searchLocation: nil)
        }
    }
    
    private func partialSearchWithText(searchText: String) {
        if searchResultsUpdating == false {
            searchResultsUpdating = true
            // Notify the delegate when a new update
            // begins
            delegate?.searchResultsDidStartUpdating()
        }
        
        guard AppContext.shared.offlineContext.state == .online else {
            return
        }
        
        GDATelemetry.track("autosuggest.request_made", with: ["context": delegate?.telemetryContext ?? ""])
        
        searchRequestToken?.cancel()
        
        //
        // Fetch autosuggest results with new search text
        //

        ///FIXME leaving this empty for now
        /// We can limit the load on the API server by only executing searches when typing is done.
        /// When "enter" is pressed, the searchWithText method below executes the query.
    }
}

// MARK: - UISearchBarDelegate

extension SearchResultsUpdater: UISearchBarDelegate {
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBarButtonClicked = true
        
        guard let searchBarText = searchBar.text, searchBarText.isEmpty == false else {
            // Return if there is no search text
            return
        }
        
        self.searchWithText(searchText: searchBarText)
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        delegate?.searchWasCancelled()
    }
    
    private func searchWithText(searchText: String) {
        // Notify the delegate when a new update
        // begins
        delegate?.searchResultsDidStartUpdating()
        
        guard AppContext.shared.offlineContext.state == .online else {
            return
        }
        
        GDATelemetry.track("search.request_made", with: ["context": delegate?.telemetryContext ?? ""])
        
        searchRequestToken?.cancel()
        
        //
        // Fetch search results given search text
        //

        // construct URL like https://photon.komoot.io/api/?q=foo&lat=38.896&lon=-77.0223&limit=7
        var searchUrl = URLComponents()
        searchUrl.scheme = "https"
        searchUrl.host = "photon.komoot.io"
        searchUrl.path = "/api"
        let baseParams = [
            URLQueryItem(name: "q", value: searchText),
            //URLQueryItem(name: "limit", value: "7")
        ]
        if let location = self.location {
            searchUrl.queryItems = baseParams + [
                URLQueryItem(name: "lat", value: String(format: "%.4f", location.coordinate.latitude)),
                URLQueryItem(name: "lon", value: String(format: "%.4f", location.coordinate.longitude)),
            ]
        } else {
            searchUrl.queryItems = baseParams
        }

        OSMServiceModel().getDynamicData(dynamicURL: searchUrl.string!, callback: searchWithTextCallback)
    }

    private func searchWithTextCallback(status: HTTPStatusCode, text: String?, error: Error?) {
        // for fetching JSON data, see Code/Data/Services/OSM/OSMServiceModel
        if status != HTTPStatusCode.success {
            return
        } //FIXME display error on failure?

        var pois: [POI] = []
        if let text = text,
           let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let features = json["features"] as? [[String: Any]] {
            for feature in features {
                guard let properties = feature["properties"] as? [String: Any],
                      let name = properties["name"] as? String,
                      let geometry = feature["geometry"] as? [String: Any],
                      let coordinates = geometry["coordinates"] as? [Double] else {
                    // Skip any results that don't have at least a name and lat/lon
                    continue
                }

                // Include as specific an address as we can get for this POI
                var addressParts: [String] = []
                for key in ["street", "city", "state", "country"] {
                    if let value = properties[key] as? String {
                        addressParts.append(value)
                    }
                }

                pois.append(GenericLocation(lat: CLLocationDegrees(floatLiteral: coordinates[1]), lon: CLLocationDegrees(floatLiteral: coordinates[0]), name: name, address: addressParts.joined(separator: ", ")))
            }
        }

        delegate?.searchResultsDidUpdate(pois, searchLocation: location)
    }
}
