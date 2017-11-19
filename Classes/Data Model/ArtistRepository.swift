//
//  ArtistRepository.swift
//  iSub
//
//  Created by Benjamin Baron on 1/14/17.
//  Copyright © 2017 Ben Baron. All rights reserved.
//

import Foundation

struct ArtistRepository: ItemRepository {
    static let si = ArtistRepository()
    fileprivate let gr = GenericItemRepository.si

    let table = "artists"
    let cachedTable = "cachedArtists"
    let itemIdField = "artistId"
    
    func artist(artistId: Int64, serverId: Int64, loadSubItems: Bool = false) -> Artist? {
        return gr.item(repository: self, itemId: artistId, serverId: serverId, loadSubItems: loadSubItems)
    }
    
    func allArtists(serverId: Int64? = nil, isCachedTable: Bool = false, loadSubItems: Bool = false) -> [Artist] {
        return gr.allItems(repository: self, serverId: serverId, isCachedTable: isCachedTable, loadSubItems: loadSubItems)
    }
    
    @discardableResult func deleteAllArtists(serverId: Int64?) -> Bool {
        return gr.deleteAllItems(repository: self, serverId: serverId)
    }
    
    func isPersisted(artist: Artist, isCachedTable: Bool = false) -> Bool {
        return gr.isPersisted(repository: self, item: artist, isCachedTable: isCachedTable)
    }
    
    func isPersisted(artistId: Int64, serverId: Int64, isCachedTable: Bool = false) -> Bool {
        return gr.isPersisted(repository: self, itemId: artistId, serverId: serverId, isCachedTable: isCachedTable)
    }
    
    func hasCachedSubItems(artist: Artist) -> Bool {
        return gr.hasCachedSubItems(repository: self, item: artist)
    }
    
    func delete(artist: Artist, isCachedTable: Bool = false) -> Bool {
        return gr.delete(repository: self, item: artist, isCachedTable: isCachedTable)
    }
    
    func replace(artist: Artist, isCachedTable: Bool = false) -> Bool {
        var success = true
        Database.si.write.inDatabase { db in
            do {
                let table = tableName(repository: self, isCachedTable: isCachedTable)
                let query = "REPLACE INTO \(table) VALUES (?, ?, ?, ?, ?, ?)"
                try db.executeUpdate(query, artist.artistId, artist.serverId, artist.name, n2N(artist.coverArtId), n2N(artist.albumCount), artist.albumSortOrder.rawValue)
            } catch {
                success = false
                printError(error)
            }
        }
        return success
    }
    
    func loadSubItems(artist: Artist) {
        artist.albums = AlbumRepository.si.albums(artistId: artist.artistId, serverId: artist.serverId)
    }
}

extension Artist: PersistedItem {
    convenience init(result: FMResultSet, repository: ItemRepository = ArtistRepository.si) {
        let artistId       = result.longLongInt(forColumnIndex: 0)
        let serverId       = result.longLongInt(forColumnIndex: 1)
        let name           = result.string(forColumnIndex: 2) ?? ""
        let coverArtId     = result.string(forColumnIndex: 3)
        let albumCount     = result.object(forColumnIndex: 4) as? Int
        let albumSortOrder = AlbumSortOrder(rawValue: result.long(forColumnIndex: 5)) ?? .year
        let repository     = repository as! ArtistRepository
        
        self.init(artistId: artistId, serverId: serverId, name: name, coverArtId: coverArtId, albumCount: albumCount, repository: repository)
        self.albumSortOrder = albumSortOrder
    }
    
    class func item(itemId: Int64, serverId: Int64, repository: ItemRepository = ArtistRepository.si) -> Item? {
        return (repository as? ArtistRepository)?.artist(artistId: itemId, serverId: serverId)
    }
    
    var isPersisted: Bool {
        return repository.isPersisted(artist: self)
    }
    
    var hasCachedSubItems: Bool {
        return repository.hasCachedSubItems(artist: self)
    }
    
    @discardableResult func replace() -> Bool {
        return repository.replace(artist: self)
    }
    
    @discardableResult func cache() -> Bool {
        return repository.replace(artist: self, isCachedTable: true)
    }
    
    @discardableResult func delete() -> Bool {
        return repository.delete(artist: self)
    }
    
    @discardableResult func deleteCache() -> Bool {
        return repository.delete(artist: self, isCachedTable: true)
    }
    
    func loadSubItems() {
        repository.loadSubItems(artist: self)
    }
}
