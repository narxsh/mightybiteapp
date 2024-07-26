import 'package:stackfood_multivendor/features/cart/controllers/cart_controller.dart';
import 'package:stackfood_multivendor/features/coupon/controllers/coupon_controller.dart';
import 'package:stackfood_multivendor/features/home/widgets/arrow_icon_button_widget.dart';
import 'package:stackfood_multivendor/features/home/widgets/item_card_widget.dart';
import 'package:stackfood_multivendor/features/restaurant/controllers/restaurant_controller.dart';
import 'package:stackfood_multivendor/common/models/restaurant_model.dart';
import 'package:stackfood_multivendor/features/category/controllers/category_controller.dart';
import 'package:stackfood_multivendor/features/restaurant/widgets/restaurant_info_section_widget.dart';
import 'package:stackfood_multivendor/features/restaurant/widgets/restaurant_screen_shimmer_widget.dart';
import 'package:stackfood_multivendor/helper/date_converter.dart';
import 'package:stackfood_multivendor/helper/price_converter.dart';
import 'package:stackfood_multivendor/helper/responsive_helper.dart';
import 'package:stackfood_multivendor/helper/route_helper.dart';
import 'package:stackfood_multivendor/util/dimensions.dart';
import 'package:stackfood_multivendor/util/images.dart';
import 'package:stackfood_multivendor/util/styles.dart';
import 'package:stackfood_multivendor/common/widgets/bottom_cart_widget.dart';
import 'package:stackfood_multivendor/common/widgets/menu_drawer_widget.dart';
import 'package:stackfood_multivendor/common/widgets/product_view_widget.dart';
import 'package:stackfood_multivendor/common/widgets/web_menu_bar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:math' as math;
import '../../../common/models/product_model.dart';

class RestaurantScreen extends StatefulWidget {
  final Restaurant? restaurant;
  final String slug;
  const RestaurantScreen({super.key, required this.restaurant, this.slug = ''});

  @override
  State<RestaurantScreen> createState() => _RestaurantScreenState();
}


class RestaurantScrollController extends GetxController {
  int currentCategoryIndex = 0;
  bool _sliverScrolled = false;
  bool get sliverScrolled => _sliverScrolled;
  ScrollController headerScrollController = ScrollController();

  void updateSliverScroll(bool scrolled) {
    _sliverScrolled = scrolled;
    update();
  }

  void setCurrentCategoryIndex(int index) {
    if (currentCategoryIndex != index) {
      currentCategoryIndex = index;
      _scrollToCategory(index);
      update();
    }
  }

  void _scrollToCategory(int index) {
    final screenWidth = Get.width;
    const itemWidth = 120.0; // Approximate width of each category item
    final offset = index * itemWidth - (screenWidth / 2) + (itemWidth / 2);
    headerScrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
}
class _RestaurantScreenState extends State<RestaurantScreen> {
  final ScrollController scrollController = ScrollController();
  final List<GlobalKey> _categoryKeys = [];
  final restController = Get.find<RestaurantController>();
  late RestaurantScrollController scrollStateController;
  bool isLoading = true;
  Map<int, List<Product>> categoryProducts = {};

  @override
  void initState() {
    super.initState();
    scrollStateController = Get.put(RestaurantScrollController());
    scrollController.addListener(_onScroll);
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupScrollListener();
    });
  }

  Future<void> _loadData() async {
    await initDataCall();
    setState(() {
      isLoading = false;
    });
  }

  void _onScroll() {
    double showHeaderThreshold = 670;
    if (scrollController.offset > showHeaderThreshold && !Get.find<RestaurantScrollController>().sliverScrolled) {
      Get.find<RestaurantScrollController>().updateSliverScroll(true);
    } else if (scrollController.offset <= showHeaderThreshold && Get.find<RestaurantScrollController>().sliverScrolled) {
      Get.find<RestaurantScrollController>().updateSliverScroll(false);
    }
  }

  @override
  void dispose() {
    scrollController.dispose();
    scrollController.removeListener(_onScroll);
    Get.delete<RestaurantScrollController>();
    super.dispose();
  }

  double _lastScrollOffset = 0;

  void _setupScrollListener() {
    scrollController.addListener(() {
      double viewportHeight = scrollController.position.viewportDimension;
      double scrollOffset = scrollController.offset;
      double maxVisibleFraction = 0;
      int selectedIndex = -1;
      bool isScrollingUp = scrollOffset < _lastScrollOffset;

      for (int i = 0; i < _categoryKeys.length; i++) {
        final RenderBox? renderBox = _categoryKeys[i].currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          final categoryPosition = renderBox.localToGlobal(Offset.zero);
          final categoryHeight = renderBox.size.height;

          double visibleTop = math.max(0, categoryPosition.dy);
          double visibleBottom = math.min(viewportHeight, categoryPosition.dy + categoryHeight);
          double visibleHeight = visibleBottom - visibleTop;

          double visibleFraction = visibleHeight / categoryHeight;

          if (isScrollingUp) {
            if (categoryPosition.dy + categoryHeight >= viewportHeight * 0.25 &&
                categoryPosition.dy + categoryHeight < viewportHeight) {
              selectedIndex = i;
              break;
            }
          } else {
            if (visibleFraction > 0.1 && visibleFraction > maxVisibleFraction) {
              maxVisibleFraction = visibleFraction;
              selectedIndex = i;
            }
          }

          if (categoryPosition.dy > viewportHeight) {
            break;
          }
        }
      }

      if (selectedIndex != -1) {
        scrollStateController.setCurrentCategoryIndex(selectedIndex);
      }

      _lastScrollOffset = scrollOffset;
    });
  }

  Future<void> initDataCall() async {
    final categoryController = Get.find<CategoryController>();
    final restController = Get.find<RestaurantController>();
    final couponController = Get.find<CouponController>();

    if (restController.isSearching) {
      restController.changeSearchStatus(isUpdate: false);
    }

    // Fetch restaurant details, category list, coupons, and recommended items concurrently
    await Future.wait([
      restController.getRestaurantDetails(Restaurant(id: widget.restaurant!.id), slug: widget.slug),
      categoryController.getCategoryList(true),
      couponController.getRestaurantCouponList(restaurantId: widget.restaurant!.id ?? restController.restaurant!.id!),
      restController.getRestaurantRecommendedItemList(widget.restaurant!.id ?? restController.restaurant!.id!, false),
    ]);

    // After fetching categories, fetch all category products
    if (categoryController.categoryList != null) {
      categoryProducts = await fetchAllCategoryProducts(restController);
    }
  }

  Future<Map<int, List<Product>>> fetchAllCategoryProducts(RestaurantController restController) async {
    final futures = restController.categoryList!.asMap().map((index, category) =>
        MapEntry(index, restController.getProductsForCategory(index))
    );
    final results = await Future.wait(futures.values);
    return Map.fromIterables(futures.keys, results);
  }

  @override
  Widget build(BuildContext context) {
    bool isDesktop = ResponsiveHelper.isDesktop(context);
    return Scaffold(
        appBar: isDesktop ? const WebMenuBar() : null,
        endDrawer: const MenuDrawerWidget(),
        endDrawerEnableOpenDragGesture: false,
        backgroundColor: Theme.of(context).cardColor,
        body: GetBuilder<RestaurantController>(
          builder: (restController) {
            return GetBuilder<CouponController>(
              builder: (couponController) {
                return GetBuilder<CategoryController>(
                  builder: (categoryController) {
                    Restaurant? restaurant;
                    if (restController.restaurant != null && restController.restaurant!.name != null &&
                        categoryController.categoryList != null) {
                      restaurant = restController.restaurant;
                    }
                    restController.setCategoryList();
                    bool hasCoupon = (couponController.couponList != null && couponController.couponList!.isNotEmpty);

                    return (restController.restaurant != null && restController.restaurant!.name != null && categoryController.categoryList != null)
                        ? isLoading
                        ? const RestaurantScreenShimmerWidget()
                        : CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      controller: scrollController,
                      slivers: [
                        RestaurantInfoSectionWidget(restaurant: restaurant!, restController: restController, hasCoupon: hasCoupon, scrollController: scrollController,),
                        SliverToBoxAdapter(child: Center(child: Container(
                          width: Dimensions.webMaxWidth,
                          color: Theme.of(context).cardColor,
                          child: Column(children: [
                            // isDesktop ? const SizedBox() : RestaurantDescriptionView(restaurant: restaurant),
                            restaurant.discount != null ? Container(
                              width: context.width,
                              margin: const EdgeInsets.symmetric(
                                  vertical: Dimensions.paddingSizeSmall, horizontal: Dimensions.paddingSizeLarge),
                              decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(Dimensions.radiusSmall), color: Theme.of(context).primaryColor),
                              padding: const EdgeInsets.all(Dimensions.paddingSizeSmall),
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [

                                Text(
                                  restaurant.discount!.discountType == 'percent' ? '${restaurant.discount!.discount}% ${'off'.tr}'
                                      : '${PriceConverter.convertPrice(restaurant.discount!.discount)} ${'off'.tr}',
                                  style: robotoMedium.copyWith(fontSize: Dimensions.fontSizeLarge, color: Theme.of(context).cardColor),
                                ),

                                Text(
                                  restaurant.discount!.discountType == 'percent'
                                      ? '${'enjoy'.tr} ${restaurant.discount!.discount}% ${'off_on_all_categories'.tr}'
                                      : '${'enjoy'.tr} ${PriceConverter.convertPrice(restaurant.discount!.discount)}'
                                      ' ${'off_on_all_categories'.tr}',
                                  style: robotoMedium.copyWith(fontSize: Dimensions.fontSizeSmall, color: Theme.of(context).cardColor),
                                ),
                                SizedBox(height: (restaurant.discount!.minPurchase != 0 || restaurant.discount!.maxDiscount != 0) ? 5 : 0),

                                restaurant.discount!.minPurchase != 0 ? Text(
                                  '[ ${'minimum_purchase'.tr}: ${PriceConverter.convertPrice(
                                      restaurant.discount!.minPurchase)} ]',
                                  style: robotoRegular.copyWith(fontSize: Dimensions.fontSizeExtraSmall, color: Theme.of(context).cardColor),
                                ) : const SizedBox(),

                                restaurant.discount!.maxDiscount != 0 ? Text(
                                  '[ ${'maximum_discount'.tr}: ${PriceConverter.convertPrice(restaurant.discount!.maxDiscount)} ]',
                                  style: robotoRegular.copyWith(fontSize: Dimensions.fontSizeExtraSmall, color: Theme.of(context).cardColor),
                                ) : const SizedBox(),

                                Text(
                                  '[ ${'daily_time'.tr}: ${DateConverter.convertTimeToTime(restaurant.discount!.startTime!)} '
                                      '- ${DateConverter.convertTimeToTime(restaurant.discount!.endTime!)} ]',
                                  style: robotoRegular.copyWith(fontSize: Dimensions.fontSizeExtraSmall, color: Theme.of(context).cardColor),
                                ),

                              ]),
                            ) : const SizedBox(),
                            SizedBox(height: (restaurant.announcementActive! && restaurant.announcementMessage != null) ? 0 : Dimensions.paddingSizeSmall),

                            ResponsiveHelper.isMobile(context) ? (restaurant.announcementActive! && restaurant.announcementMessage != null) ? Container(
                              decoration: const BoxDecoration(color: Colors.green),
                              padding: const EdgeInsets.symmetric(vertical: Dimensions.paddingSizeSmall, horizontal: Dimensions.paddingSizeLarge),
                              margin: const EdgeInsets.only(bottom: Dimensions.paddingSizeSmall),
                              child: Row(children: [

                                Image.asset(Images.announcement, height: 26, width: 26),
                                const SizedBox(width: Dimensions.paddingSizeSmall),

                                Flexible(child: Text(
                                  restaurant.announcementMessage ?? '',
                                  style: robotoMedium.copyWith(fontSize: Dimensions.fontSizeSmall, color: Theme.of(context).cardColor),
                                )),

                              ]),
                            ) : const SizedBox() : const SizedBox(),

                            restController.recommendedProductModel != null && restController.recommendedProductModel!.products!.isNotEmpty ? Container(
                              color: Theme.of(context).primaryColor.withOpacity(0.10),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: Dimensions.paddingSizeLarge, left: Dimensions.paddingSizeLarge,
                                    bottom: Dimensions.paddingSizeSmall, right: Dimensions.paddingSizeLarge,
                                  ),
                                  child: Row(children: [
                                    Expanded(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text('recommend_for_you'.tr, style: robotoMedium.copyWith(
                                            fontSize: Dimensions.fontSizeLarge, fontWeight: FontWeight.w700)),
                                        const SizedBox(height: Dimensions.paddingSizeExtraSmall),

                                        Text('here_is_what_you_might_like_to_test'.tr, style: robotoRegular.copyWith(
                                            fontSize: Dimensions.fontSizeSmall, color: Theme.of(context).disabledColor)),
                                      ]),
                                    ),

                                    ArrowIconButtonWidget(
                                      onTap: () => Get.toNamed(RouteHelper.getPopularFoodRoute(false, fromIsRestaurantFood: true, restaurantId: widget.restaurant!.id
                                          ?? Get.find<RestaurantController>().restaurant!.id!)),
                                    ),
                                  ]),
                                ),

                                SizedBox(
                                  height: ResponsiveHelper.isDesktop(context) ? 307 : 305, width: context.width,
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                    scrollDirection: Axis.horizontal,
                                    itemCount: restController.recommendedProductModel!.products!.length,
                                    physics: const BouncingScrollPhysics(),
                                    padding: const EdgeInsets.only(top: Dimensions.paddingSizeExtraSmall,
                                        bottom: Dimensions.paddingSizeExtraSmall,
                                        right: Dimensions.paddingSizeDefault),
                                    itemBuilder: (context, index) {
                                      return Padding(
                                        padding: const EdgeInsets.only(left: Dimensions.paddingSizeDefault),
                                        child: ItemCardWidget(
                                          product: restController.recommendedProductModel!.products![index],
                                          isBestItem: false,
                                          isPopularNearbyItem: false,
                                          width: ResponsiveHelper.isDesktop(context) ? 200 : MediaQuery.of(context).size.width * 0.53,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: Dimensions.paddingSizeSmall),

                              ]),
                            ) : const SizedBox(),
                          ]),
                        ))),
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: SliverDelegate(
                            height: 50,
                            child: GetBuilder<RestaurantScrollController>(
                              builder: (scrollState) {
                                return AnimatedOpacity(
                                  opacity: scrollState.sliverScrolled ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 300),
                                  child: Container(
                                    color: Theme.of(context).cardColor,
                                    child: Center(
                                      child: Container(
                                        width: Dimensions.webMaxWidth,
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).cardColor,
                                          boxShadow: isDesktop ? [] : [
                                            BoxShadow(color: Colors.grey.withOpacity(0.1), spreadRadius: 1, blurRadius: 10, offset: const Offset(0, 1)),
                                          ],
                                        ),
                                        padding: const EdgeInsets.symmetric(vertical: Dimensions.paddingSizeExtraSmall),
                                        child: SingleChildScrollView(
                                          controller: scrollState.headerScrollController,
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: List.generate(
                                              restController.categoryList!.length,
                                                  (index) => GestureDetector(
                                                onTap: () {
                                                  if (_categoryKeys.length > index) {
                                                    Scrollable.ensureVisible(
                                                      _categoryKeys[index].currentContext!,
                                                      duration: const Duration(milliseconds: 300),
                                                      curve: Curves.easeInOut,
                                                    );
                                                  }
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: Dimensions.paddingSizeSmall, vertical: Dimensions.paddingSizeExtraSmall),
                                                  margin: const EdgeInsets.only(right: Dimensions.paddingSizeSmall),
                                                  decoration: BoxDecoration(
                                                    borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
                                                    color: index == scrollState.currentCategoryIndex ? Theme.of(context).primaryColor.withOpacity(0.1) : Colors.transparent,
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      restController.categoryList![index].name!,
                                                      style: index == scrollState.currentCategoryIndex
                                                          ? robotoMedium.copyWith(fontSize: Dimensions.fontSizeSmall, color: Theme.of(context).primaryColor)
                                                          : robotoRegular.copyWith(fontSize: Dimensions.fontSizeSmall, color: Theme.of(context).disabledColor),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: restController.categoryList!.length,
                            itemBuilder: (context, index) {
                              final currentCategory = restController.categoryList![index];
                              final products = categoryProducts[index] ?? [];

                              if (_categoryKeys.length <= index) {
                                _categoryKeys.add(GlobalKey());
                              }

                              return Padding(
                                key: _categoryKeys[index],
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Dimensions.paddingSizeExtraSmall,
                                  vertical: Dimensions.paddingSizeExtraSmall,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      currentCategory.name!,
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 10),
                                    ProductViewWidget(
                                      isRestaurant: false,
                                      restaurants: null,
                                      products: products,
                                      inRestaurantPage: true,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        )
                      ],
                    )
                        : const RestaurantScreenShimmerWidget();
                  },
                );
              },
            );
          },
        ),
        bottomNavigationBar: GetBuilder<CartController>(builder: (cartController) {
          return cartController.cartList.isNotEmpty && !isDesktop ? BottomCartWidget(restaurantId: cartController.cartList[0].product!.restaurantId!) : const SizedBox();
        })
    );
  }
}

class SliverDelegate extends SliverPersistentHeaderDelegate {
  Widget child;
  double height;

  SliverDelegate({required this.child, this.height = 100});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  double get maxExtent => height;

  @override
  double get minExtent => height;

  @override
  bool shouldRebuild(SliverDelegate oldDelegate) {
    return oldDelegate.maxExtent != height || oldDelegate.minExtent != height || child != oldDelegate.child;
  }
}
