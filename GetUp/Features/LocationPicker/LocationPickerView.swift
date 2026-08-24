import MapKit
import SwiftUI

@MainActor
struct LocationPickerView: View {
    @Bindable private var model: LocationPickerModel
    @Binding private var radius: RadiusOption

    private let onRequestPlaceName: () -> Void
    private let onApply: () -> Void
    private let onOpenSettings: () -> Void

    @State private var cameraPosition: MapCameraPosition
    @State private var visibleCenter: ReferenceLocation
    @State private var pendingProgrammaticCenter: ReferenceLocation?
    @State private var isLocating = false

    init(
        model: LocationPickerModel,
        radius: Binding<RadiusOption>,
        onRequestPlaceName: @escaping () -> Void,
        onApply: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.model = model
        self._radius = radius
        self.onRequestPlaceName = onRequestPlaceName
        self.onApply = onApply
        self.onOpenSettings = onOpenSettings
        self._cameraPosition = State(
            initialValue: .region(
                Self.cameraRegion(
                    centeredAt: model.cameraCenter,
                    radius: radius.wrappedValue
                )
            )
        )
        self._visibleCenter = State(initialValue: model.cameraCenter)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                mapCard
                savedPlaceChoices

                if let guidance = model.guidance {
                    guidanceCard(for: guidance)
                }

                RadiusPicker(selection: $radius)
                applyButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(FocusColor.background.ignoresSafeArea())
        .foregroundStyle(FocusColor.textPrimary)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(FocusColor.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onChange(of: radius) { _, newRadius in
            moveCamera(to: model.cameraCenter, radius: newRadius)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LOCATION CONDITION")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(FocusColor.accent)

            Text("장소 선택")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("위치와 반경을 설정해주세요")
                .font(.subheadline)
                .foregroundStyle(FocusColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var mapCard: some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
            if model.pinCandidate != nil {
                MapCircle(center: visibleCenter.coordinate, radius: radius.meters)
                    .foregroundStyle(FocusColor.accent.opacity(0.18))
                    .stroke(FocusColor.accent, lineWidth: 2)
            }
        }
        .onMapCameraChange(frequency: .continuous) { context in
            visibleCenter = ReferenceLocation(context.region.center)
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            let settledCenter = ReferenceLocation(context.region.center)
            visibleCenter = settledCenter

            if let pendingProgrammaticCenter,
               pendingProgrammaticCenter.isApproximatelyEqual(to: settledCenter)
            {
                self.pendingProgrammaticCenter = nil
                return
            }

            pendingProgrammaticCenter = nil
            model.mapDidSettle(at: settledCenter)
        }
        .overlay {
            VStack(spacing: 10) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(FocusColor.accent, FocusColor.background)
                    .accessibilityHidden(true)

                Text("반경 \(radius.displayName)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(FocusColor.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(FocusColor.background, in: .capsule)
                    .accessibilityHidden(true)
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            currentLocationButton
                .padding()
        }
        .aspectRatio(353 / 402, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 24))
        .accessibilityLabel("기준 위치 지도")
        .accessibilityValue("선택된 반경 \(radius.displayName)")
        .accessibilityHint("지도를 이동하면 화면 중앙 좌표가 기준 위치로 선택됩니다.")
        .accessibilityIdentifier("locationPicker.map")
    }

    private var currentLocationButton: some View {
        Button {
            Task {
                isLocating = true
                await model.useCurrentLocation()
                isLocating = false

                if model.guidance == nil {
                    moveCamera(to: model.cameraCenter, radius: radius)
                }
            }
        } label: {
            if isLocating {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "location")
            }
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .tint(FocusColor.textPrimary)
        .foregroundStyle(FocusColor.background)
        .disabled(isLocating)
        .accessibilityLabel("현재 위치로 이동")
        .accessibilityValue(currentLocationAccessibilityValue)
        .accessibilityHint("현재 위치를 지도 중앙의 기준 위치로 선택합니다.")
        .accessibilityIdentifier("locationPicker.currentLocation")
    }

    @ViewBuilder
    private var savedPlaceChoices: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.savedPlaces, id: \.id) { place in
                    savedPlaceButton(place)
                }

                Button("직접 입력", systemImage: "chevron.forward") {
                    onRequestPlaceName()
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(LocationChoiceButtonStyle(isSelected: false))
                .accessibilityHint("현재 지도 좌표에 새 장소 이름을 입력합니다.")
                .accessibilityIdentifier("locationPicker.customPlace")
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("저장 장소")
    }

    private func savedPlaceButton(_ place: SavedPlaceSnapshot) -> some View {
        let isSelected = model.selectedSavedPlaceID == place.id

        return Button(place.name) {
            model.selectSavedPlace(id: place.id)
            moveCamera(to: place.coordinate, radius: radius)
        }
        .buttonStyle(LocationChoiceButtonStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("저장된 장소를 기준 위치로 선택합니다.")
        .accessibilityIdentifier(place.accessibilityIdentifier)
    }

    private func guidanceCard(for guidance: LocationPickerGuidance) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: guidance.systemImage)
                .foregroundStyle(FocusColor.error)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(guidance.message)
                    .font(.footnote)
                    .foregroundStyle(FocusColor.textPrimary)

                if guidance == .whenInUseRequired {
                    Button("설정 열기", action: onOpenSettings)
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(FocusColor.accent)
                        .accessibilityHint("GetUp의 위치 권한을 변경할 수 있는 시스템 설정을 엽니다.")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(FocusColor.surfaceElevated, in: .rect(cornerRadius: 16))
        .accessibilityIdentifier("locationPicker.guidance")
    }

    private var applyButton: some View {
        Button("적용") {
            if !model.placeName.isEmpty {
                model.confirm(placeName: model.placeName)
                if model.completion != nil {
                    onApply()
                }
            } else {
                onRequestPlaceName()
            }
        }
        .font(.body)
        .fontWeight(.bold)
        .frame(maxWidth: .infinity, minHeight: 56)
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 18))
        .tint(FocusColor.accent)
        .foregroundStyle(FocusColor.background)
        .disabled(!model.canConfirmPinSelection)
        .accessibilityHint(applyAccessibilityHint)
        .accessibilityIdentifier("locationPicker.confirm")
    }

    private var currentLocationAccessibilityValue: String {
        switch model.guidance {
        case .whenInUseRequired:
            "위치 권한 필요"
        case .locationUnavailable:
            "현재 위치 확인 불가"
        case .placeNameRequired, nil:
            isLocating ? "확인 중" : "사용 가능"
        }
    }

    private var applyAccessibilityHint: String {
        model.placeName.isEmpty
            ? "현재 좌표를 유지하고 장소 이름 입력 화면으로 이동합니다."
            : "선택한 저장 장소와 반경을 규칙에 적용합니다."
    }

    private func moveCamera(to coordinate: ReferenceLocation, radius: RadiusOption) {
        visibleCenter = coordinate
        pendingProgrammaticCenter = coordinate
        cameraPosition = .region(
            Self.cameraRegion(centeredAt: coordinate, radius: radius)
        )
    }

    private static func cameraRegion(
        centeredAt coordinate: ReferenceLocation,
        radius: RadiusOption
    ) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate.coordinate,
            latitudinalMeters: max(radius.meters * 3.2, 1_600),
            longitudinalMeters: max(radius.meters * 3.2, 1_600)
        )
    }
}

private struct LocationChoiceButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .fontWeight(.bold)
            .foregroundStyle(isSelected ? FocusColor.background : FocusColor.textPrimary)
            .padding(.horizontal, 24)
            .frame(minHeight: 44)
            .background(
                isSelected ? FocusColor.accent : FocusColor.surfaceElevated,
                in: .capsule
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private enum FocusColor {
    static let background = Color(red: 8 / 255, green: 9 / 255, blue: 11 / 255)
    static let surfaceElevated = Color(red: 32 / 255, green: 35 / 255, blue: 41 / 255)
    static let accent = Color(red: 244 / 255, green: 214 / 255, blue: 0)
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 166 / 255, green: 168 / 255, blue: 173 / 255)
    static let error = Color(red: 255 / 255, green: 105 / 255, blue: 97 / 255)
}

private extension ReferenceLocation {
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func isApproximatelyEqual(to other: ReferenceLocation) -> Bool {
        abs(latitude - other.latitude) < 0.0001
            && abs(longitude - other.longitude) < 0.0001
    }
}

private extension RadiusOption {
    var displayName: String {
        switch self {
        case .meters500:
            "500m"
        case .meters1000:
            "1km"
        case .meters2000:
            "2km"
        case .meters3000:
            "3km"
        case .meters4000:
            "4km"
        case .meters5000:
            "5km"
        }
    }
}

private extension SavedPlaceSnapshot {
    var accessibilityIdentifier: String {
        switch name {
        case "집":
            "locationPicker.savedPlace.home"
        case "회사":
            "locationPicker.savedPlace.work"
        default:
            "locationPicker.savedPlace.\(id.uuidString)"
        }
    }
}

private extension LocationPickerGuidance {
    var message: String {
        switch self {
        case .whenInUseRequired:
            "현재 위치를 사용할 수 없어요. 지도 핀으로 직접 설정할 수 있어요."
        case .locationUnavailable:
            "현재 위치를 확인하지 못했어요. 지도 핀을 이동해 직접 설정해 주세요."
        case .placeNameRequired:
            "다른 규칙에서도 사용할 수 있도록 장소 이름을 입력해 주세요."
        }
    }

    var systemImage: String {
        switch self {
        case .whenInUseRequired:
            "location.slash"
        case .locationUnavailable:
            "location.magnifyingglass"
        case .placeNameRequired:
            "exclamationmark.circle"
        }
    }
}
