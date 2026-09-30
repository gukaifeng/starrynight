import Foundation

/// Three-way reconciliation: the last acknowledgement, current local value,
/// and incoming server value. In particular, an unchanged server value must
/// never replace an unsent local edit.
enum AccountSyncMerge {
    enum Decision { case apply, keepLocal, conflict, stale }
    static func decide(knownVersion:Int?,known:JSONValue?,pending:JSONValue?,remoteVersion:Int,remote:JSONValue)->Decision {
        if remoteVersion>0,let knownVersion,remoteVersion<knownVersion{return .stale}
        guard let pending,pending != remote else{return .apply}
        if let known,known != remote{return .conflict}
        return .keepLocal
    }
    static func diff(old:JSONValue,new:JSONValue)->JSONValue {
        guard let lhs=old.object,let rhs=new.object else{return new}
        var patch:[String:JSONValue]=[:]
        for key in Set(lhs.keys).union(rhs.keys) where lhs[key] != rhs[key] {
            patch[key]=rhs[key].map{diff(old:lhs[key] ?? .null,new:$0)} ?? .null
        }
        return .object(patch)
    }
    static func overlay(known:JSONValue,on old:JSONValue)->JSONValue {
        guard let value=known.object,let original=old.object else{return known}
        var merged=original
        for (key,item) in value{merged[key]=overlay(known:item,on:original[key] ?? .null)}
        return .object(merged)
    }
}
