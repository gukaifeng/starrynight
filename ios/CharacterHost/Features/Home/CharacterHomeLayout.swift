import Foundation
import CoreGraphics

/// A fixed, paged gallery. Capacity is derived from both available dimensions.
struct CharacterHomeLayout: Equatable {
    let columns: Int
    let rows: Int
    let capacity: Int
    let pages: Int
    let card: CGSize
    let gap: CGFloat
    var gridHeight: CGFloat { card.height * CGFloat(rows) + gap * CGFloat(rows-1) }

    init(size: CGSize, count: Int, largeText: Bool = false) {
        let width = max(1,size.width), height = max(1,size.height)
        let gap: CGFloat = width < 600 ? 12 : 20
        let minimumWidth: CGFloat = largeText ? 205 : 154
        let minimumHeight: CGFloat = largeText ? 290 : 230
        let maxColumns = max(1,min(4,max(1,count),Int((width+gap)/(minimumWidth+gap))))
        let maxRows = max(1,min(3,Int((height+gap)/(minimumHeight+gap))))
        var best = (columns:1,rows:1,score:-Double.infinity,card:CGSize.zero)
        for columns in 1...maxColumns {
            for rows in 1...maxRows {
                let capacity = columns * rows
                // Do not reserve whole empty rows or make a lone second-row card when a balanced grid fits.
                guard rows == 1 || count > columns * (rows-1) else { continue }
                let cardWidth = (width-gap*CGFloat(columns-1))/CGFloat(columns)
                let cardHeight = min(width >= 600 ? 410 : 340,(height-gap*CGFloat(rows-1))/CGFloat(rows))
                let visible = min(max(1,count),capacity)
                let empty = capacity-visible
                let shape = abs(log(max(0.01,Double(cardWidth/cardHeight))/0.78))
                let score = Double(visible)*100 - Double(empty)*12 - shape*20
                if score > best.score { best = (columns,rows,score,CGSize(width:cardWidth,height:cardHeight)) }
            }
        }
        self.columns = best.columns; self.rows = best.rows
        capacity = best.columns*best.rows; pages = max(1,(count+capacity-1)/capacity)
        card = best.card; self.gap = gap
    }
    func page(after current:Int,translation:CGFloat,predicted:CGFloat,width:CGFloat) -> Int {
        let direction=abs(translation)>width*0.18 ? translation : abs(predicted)>width*0.4 ? predicted : 0
        return min(pages-1,max(0,current+(direction<0 ? 1 : direction>0 ? -1 : 0)))
    }
    func page(containing index: Int) -> Int { min(pages-1,max(0,index)/capacity) }
}
