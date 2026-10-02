-- Eight prototype variants, with a shared box silhouette for each species.
local styles = {
    C01 = {shape = "Foxling", body = {245, 158, 81}, accent = {255, 230, 175}, marks = 1},
    C02 = {shape = "Shellkin", body = {105, 201, 178}, accent = {52, 128, 165}, marks = 1},
    C03 = {shape = "Foxling", body = {119, 200, 235}, accent = {222, 246, 255}, marks = 2},
    C04 = {shape = "Shellkin", body = {173, 120, 105}, accent = {244, 135, 75}, marks = 2},
    C05 = {shape = "Foxling", body = {238, 182, 59}, accent = {255, 243, 172}, marks = 3},
    C06 = {shape = "Shellkin", body = {77, 146, 217}, accent = {99, 224, 232}, marks = 3},
    C07 = {shape = "Foxling", body = {155, 147, 227}, accent = {220, 242, 255}, marks = 4},
    C08 = {shape = "Shellkin", body = {96, 77, 97}, accent = {255, 115, 68}, marks = 4},
}
for _, style in pairs(styles) do
    table.freeze(style.body); table.freeze(style.accent); table.freeze(style)
end
return table.freeze(styles)
