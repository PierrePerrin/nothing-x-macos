//
//  NothingRepository.swift
//  Nothing X MacOS
//
//  Created by Daniel on 2025/2/25.
//

import Foundation


protocol NothingRepository {
    
    func getSaved() -> [NothingDeviceEntity]
    
    func save(device: NothingDeviceEntity)
    
    func delete(device: NothingDeviceEntity)
    
    func contains(mac: String) -> Bool
    
    /// Looks up a saved device by MAC across all saved devices (not just the recent ones returned by getSaved()).
    func find(mac: String) -> NothingDeviceEntity?
    
    func delete(mac: String)

    
}
