//
//  DownloadQueueViewModel.swift
//  iSub
//
//  Created by Benjamin Baron on 3/18/17.
//  Copyright © 2017 Ben Baron. All rights reserved.
//

import Foundation

final class DownloadQueueViewModel: ItemViewModel {
    override func cellActionSheet(forItem item: Item, indexPath: IndexPath) -> UIAlertController {
        let actionSheet = super.cellActionSheet(forItem: item, indexPath: indexPath)
        
        self.addPlayQueueActions(toActionSheet: actionSheet, forItem: item, indexPath: indexPath)
        self.addGoToRelatedActions(toActionSheet: actionSheet, forItem: item, indexPath: indexPath)
        
        if let song = item as? Song {
            actionSheet.addAction(UIAlertAction(title: "Remove", style: .destructive) { action in
                DownloadQueue.si.remove(song: song)
                self.loadModelsFromDatabase()
                self.delegate?.itemsChanged(viewModel: self)
            })
            actionSheet.addAction(UIAlertAction(title: "Remove All", style: .destructive) { action in
                for songToRemove in self.songs {
                    DownloadQueue.si.remove(song: songToRemove)
                }
                self.loadModelsFromDatabase()
                self.delegate?.itemsChanged(viewModel: self)
            })
        }
                
        return actionSheet
    }
}
